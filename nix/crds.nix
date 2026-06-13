{
  lib,
  flake-parts-lib,
  config,
  ...
}:
let
  flakeConfig = config;
  inherit (flake-parts-lib) mkPerSystemOption;
in
{
  options = {
    perSystem = mkPerSystemOption {
      options.kubenix.crds = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        example = lib.literalExpression ''
          [
            ./vendor/flux/install.yaml
            ./vendor/flux-operator/install.yaml
          ]
        '';
      };
    };
    kubenix = {
      crdAttrNameOverrides = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          Override generated Kubenix resource attr names for CRDs.

          Keys are "<group>/<version>/<kind>".
          Values are the attr names used under kubernetes.resources.
        '';
        example = lib.literalExpression ''
          {
            "postgresql.cnpg.io/v1/Cluster" = "cnpgClusters";
          }
        '';
      };
      crdAttrNamePrefixOverrides = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          Prefix generated Kubenix resource attr names for every CRD in an API group.

          Keys are API groups, like "postgresql.cnpg.io".
          Values are attr prefixes, like "cnpg".
        '';
        example = lib.literalExpression ''
          {
            "postgresql.cnpg.io" = "cnpg";
          }
        '';
      };
    };
  };

  config = {
    perSystem =
      {
        config,
        pkgs,
        ...
      }:
      let
        crdsJson =
          builtins.filter (manifest: manifest != null && (manifest.kind == "CustomResourceDefinition"))
            (
              lib.flatten (
                builtins.map (
                  manifest:
                  lib.importJSON (
                    pkgs.runCommand "yaml-to-json" { } ''
                      ${pkgs.yq}/bin/yq -c . ${manifest} > out
                      sed -e 's/$/,/' -i out
                      sed '$ s/.$//' -i out
                      echo "[$(cat out)]" > $out
                    ''
                  )
                ) config.kubenix.crds
              )
            );

        kubenixCrdCustomTypes =
          let
            processCrdVersion =
              crd: version:
              let
                crdKey = "${crd.spec.group}/${version.name}/${crd.spec.names.kind}";
                prefix = flakeConfig.kubenix.crdAttrNamePrefixOverrides.${crd.spec.group} or null;

                defaultAttrName =
                  if prefix != null then
                    "${prefix}${lib.strings.toSentenceCase crd.spec.names.plural}"
                  else
                    crd.spec.names.plural;
              in
              {
                inherit (crd.spec) group;
                version = version.name;
                inherit (crd.spec.names) kind;
                attrName = flakeConfig.kubenix.crdAttrNameOverrides.${crdKey} or defaultAttrName;
                schema = version.schema.openAPIV3Schema;
              };
            processCrd = crd: builtins.map (version: processCrdVersion crd version) crd.spec.versions;
            schemasFlattened = builtins.concatMap processCrd crdsJson;

            schemaType =
              schema:
              if (schema."x-kubernetes-int-or-string" or false) == true then
                lib.types.either lib.types.int lib.types.str
              else if schema ? oneOf || schema ? anyOf || schema ? allOf then
                lib.types.anything
              else if schema ? type then
                if schema.type == "string" then
                  lib.types.str
                else if schema.type == "integer" || schema.type == "number" then
                  lib.types.int
                else if schema.type == "boolean" then
                  lib.types.bool
                else if schema.type == "array" then
                  lib.types.listOf (schemaType (schema.items or { type = "object"; }))
                else if schema.type == "object" then
                  if schema ? properties then
                    lib.types.submodule (
                      _:
                      {
                        options = schemaOptions schema;
                      }
                      // lib.optionalAttrs ((schema.additionalProperties or false) == true) {
                        freeformType = lib.types.attrs;
                      }
                    )
                  else if schema ? additionalProperties && builtins.isAttrs schema.additionalProperties then
                    lib.types.attrsOf (schemaType schema.additionalProperties)
                  else
                    lib.types.attrs
                else
                  lib.types.anything
              else if schema ? properties then
                lib.types.submodule (_: {
                  options = schemaOptions schema;
                })
              else
                lib.types.anything;

            schemaOptions =
              schema:
              let
                properties = schema.properties or { };
                required = schema.required or [ ];
              in
              builtins.mapAttrs (
                propName: propSchema:
                lib.mkOption {
                  type =
                    if builtins.elem propName required then
                      schemaType propSchema
                    else
                      lib.types.nullOr (schemaType propSchema);
                  default = null;
                }
              ) properties;
          in
          builtins.map (crdVersion: {
            inherit (crdVersion)
              group
              version
              kind
              attrName
              ;
            module = {
              options = schemaOptions (crdVersion.schema.properties.spec or { type = "object"; });
              freeformType = lib.types.attrs;
            };
          }) schemasFlattened;
      in
      {
        _module.args.kubenixCrdCustomTypes = kubenixCrdCustomTypes;

        packages.crds = pkgs.writeTextFile {
          name = "crds.json";
          text = builtins.toJSON crdsJson;
        };
      };
  };
}
