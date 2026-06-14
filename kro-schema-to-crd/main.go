package main

import (
	"fmt"
	"maps"
	"os"
	"strings"

	"github.com/alecthomas/kong"
	"github.com/kubernetes-sigs/kro/pkg/simpleschema"
	extv1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/yaml"
)

type Context struct{}

type GenerateCmd struct {
	RGD string `arg:"" name:"rgd" help:"Path to a ResourceGraphDefinition YAML or JSON file." type:"path"`
}

type ResourceGraphDefinition struct {
	Spec ResourceGraphDefinitionSpec `json:"spec"`
}

type ResourceGraphDefinitionSpec struct {
	Schema ResourceGraphDefinitionSchema `json:"schema"`
}

type ResourceGraphDefinitionSchema struct {
	APIVersion string                                   `json:"apiVersion"`
	Group      string                                   `json:"group,omitempty"`
	Kind       string                                   `json:"kind"`
	Scope      string                                   `json:"scope,omitempty"`
	Spec       map[string]any                           `json:"spec"`
	Types      map[string]any                           `json:"types,omitempty"`
	Columns    []extv1.CustomResourceColumnDefinition   `json:"additionalPrinterColumns,omitempty"`
	Metadata   ResourceGraphDefinitionSchemaCRDMetadata `json:"metadata"`
}

type ResourceGraphDefinitionSchemaCRDMetadata struct {
	Labels      map[string]string `json:"labels,omitempty"`
	Annotations map[string]string `json:"annotations,omitempty"`
}

func (g *GenerateCmd) Run(ctx *Context) error {
	raw, err := os.ReadFile(g.RGD)
	if err != nil {
		return fmt.Errorf("read RGD: %w", err)
	}

	var rgd ResourceGraphDefinition
	if err := yaml.Unmarshal(raw, &rgd); err != nil {
		return fmt.Errorf("parse RGD: %w", err)
	}

	crd, err := buildCRD(rgd.Spec.Schema)
	if err != nil {
		return err
	}

	out, err := yaml.Marshal(crd)
	if err != nil {
		return fmt.Errorf("marshal CRD: %w", err)
	}

	fmt.Print(string(out))
	return nil
}

func buildCRD(schema ResourceGraphDefinitionSchema) (*extv1.CustomResourceDefinition, error) {
	if schema.APIVersion == "" {
		return nil, fmt.Errorf("spec.schema.apiVersion is required")
	}

	if schema.Kind == "" {
		return nil, fmt.Errorf("spec.schema.kind is required")
	}

	if len(schema.Spec) == 0 {
		return nil, fmt.Errorf("spec.schema.spec is required")
	}

	group := schema.Group
	if group == "" {
		group = "kro.run"
	}

	scope, err := parseScope(schema.Scope)
	if err != nil {
		return nil, err
	}

	specSchema, err := simpleschema.ToOpenAPISpec(schema.Spec, schema.Types)
	if err != nil {
		return nil, fmt.Errorf("convert spec SimpleSchema to OpenAPI: %w", err)
	}

	preserveUnknownFields := true
	pluralName := plural(schema.Kind)

	annotations := map[string]string{
		"kro-typegen.bitbloxhub.dev/generated": "true",
		"kro-typegen.bitbloxhub.dev/apply":     "false",
	}

	maps.Copy(annotations, schema.Metadata.Annotations)

	crd := &extv1.CustomResourceDefinition{
		TypeMeta: metav1.TypeMeta{
			APIVersion: "apiextensions.k8s.io/v1",
			Kind:       "CustomResourceDefinition",
		},
		ObjectMeta: metav1.ObjectMeta{
			Name:        pluralName + "." + group,
			Labels:      schema.Metadata.Labels,
			Annotations: annotations,
		},
		Spec: extv1.CustomResourceDefinitionSpec{
			Group: group,
			Scope: scope,
			Names: extv1.CustomResourceDefinitionNames{
				Kind:     schema.Kind,
				ListKind: schema.Kind + "List",
				Plural:   pluralName,
				Singular: strings.ToLower(schema.Kind),
			},
			Versions: []extv1.CustomResourceDefinitionVersion{
				{
					Name:                     schema.APIVersion,
					Served:                   true,
					Storage:                  true,
					AdditionalPrinterColumns: schema.Columns,
					Subresources: &extv1.CustomResourceSubresources{
						Status: &extv1.CustomResourceSubresourceStatus{},
					},
					Schema: &extv1.CustomResourceValidation{
						OpenAPIV3Schema: &extv1.JSONSchemaProps{
							Type: "object",
							Properties: map[string]extv1.JSONSchemaProps{
								"apiVersion": {
									Type: "string",
								},
								"kind": {
									Type: "string",
								},
								"metadata": {
									Type: "object",
								},
								"spec": *specSchema,
								"status": {
									Type:                   "object",
									XPreserveUnknownFields: &preserveUnknownFields,
								},
							},
						},
					},
				},
			},
		},
	}

	return crd, nil
}

func parseScope(scope string) (extv1.ResourceScope, error) {
	switch strings.ToLower(scope) {
	case "", "namespaced":
		return extv1.NamespaceScoped, nil
	case "cluster":
		return extv1.ClusterScoped, nil
	default:
		return "", fmt.Errorf("unsupported spec.schema.scope %q; expected Namespaced or Cluster", scope)
	}
}

func plural(kind string) string {
	name := strings.ToLower(kind)

	if strings.HasSuffix(name, "s") {
		return name + "es"
	}

	if base, ok := strings.CutSuffix(name, "y"); ok {
		return base + "ies"
	}

	return name + "s"
}

var cli struct {
	Generate GenerateCmd `cmd:"" help:"Generate CRD from RGD. Outputs to stdout."`
}

func main() {
	ctx := kong.Parse(
		&cli,
		kong.Name("kro-schema-to-crd"),
		kong.Description("Generate a synthetic CRD from a kro ResourceGraphDefinition for Kubenix typegen."),
	)

	err := ctx.Run(&Context{})
	ctx.FatalIfErrorf(err)
}
