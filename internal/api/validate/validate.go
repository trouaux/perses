// Copyright 2024 The Perses Authors
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package validate

import (
	"fmt"
	"regexp"

	"github.com/perses/perses/internal/api/plugin/schema"
	modelV1 "github.com/perses/perses/pkg/model/api/v1"
	"github.com/perses/perses/pkg/model/api/v1/common"
	"github.com/perses/perses/pkg/model/api/v1/dashboard"
	"github.com/perses/perses/pkg/model/api/v1/datasource"
	"github.com/perses/perses/pkg/model/api/v1/utils"
)

// We want to keep only variables that are not only a number.
// A number that represents a variable is not meaningful, and so we don't want to consider it.
// It's also a way to avoid a collision in terms of variable syntax.
// For example, in PromQL, the function `label_replace` uses the syntax "$1", "$2" for the placeholders.
var variableNameRegexp = regexp.MustCompile(`^\w*?[^0-9]\w*$`)

func DashboardSpec(spec modelV1.DashboardSpec, sch schema.Schema) error {
	if _, err := utils.BuildVariableOrder(spec.Variables, nil, nil); err != nil {
		return err
	}
	return validateDashboardSpec(spec, sch)

}

func DashboardSpecWithVars(spec modelV1.DashboardSpec, sch schema.Schema, projectVariables []*modelV1.Variable, globalVariables []*modelV1.GlobalVariable) error {
	if _, err := utils.BuildVariableOrder(spec.Variables, projectVariables, globalVariables); err != nil {
		return err
	}

	return validateDashboardSpec(spec, sch)
}

func Datasource[T modelV1.DatasourceInterface](entity T, list []T, sch schema.Schema) error {
	if err := validateDatasourcePlugin(entity.GetDatasourceSpec().Plugin, entity.GetMetadata().GetName(), sch); err != nil {
		return err
	}
	if list != nil {
		return validateUnicityOfDefaultDTS(entity, list)
	}
	return nil
}

func Variable(entity modelV1.VariableInterface, sch schema.Schema) error {
	if err := validateVariableName(entity.GetMetadata().GetName()); err != nil {
		return err
	}
	return sch.ValidateGlobalVariable(entity.GetVarSpec())
}

func validateUnicityOfDefaultDTS[T modelV1.DatasourceInterface](entity T, list []T) error {
	name := entity.GetMetadata().GetName()
	spec := entity.GetDatasourceSpec()
	// Since the entity is not supposed to be a default datasource, no need to verify if there is another one already defined as default
	if !spec.Default {
		return nil
	}
	entityPluginKind := spec.Plugin.Kind
	for _, dts := range list {
		if name == dts.GetMetadata().GetName() {
			// nothing to check if comparing with same datasource
			continue
		}
		dtsSpec := dts.GetDatasourceSpec()
		if dtsSpec.Default && dtsSpec.Plugin.Kind == entityPluginKind {
			return fmt.Errorf("datasource %q cannot be a default %q because there is already one defined named %q", entity.GetMetadata().GetName(), entityPluginKind, dts.GetMetadata().GetName())
		}
	}
	return nil
}

func validateVariableName(variable string) error {
	valid := variableNameRegexp.MatchString(variable)
	if !valid {
		return fmt.Errorf("variable name '%s' is not valid", variable)
	}

	// Checking if the variable does not have builtin variable prefix: __
	isBuiltinVar := modelV1.IsBuiltinVariable(variable)
	if isBuiltinVar {
		return fmt.Errorf("variable name '%s' can not have builtin variable prefix: __", variable)
	}
	return nil
}

func validateVariableNames(variables []dashboard.Variable) error {
	for _, variable := range variables {
		if err := validateVariableName(variable.Spec.GetName()); err != nil {
			return err
		}
	}
	return nil
}

func validateDatasourcePlugin(plugin common.Plugin, name string, sch schema.Schema) error {
	if _, _, err := datasource.ValidateAndExtract(plugin.Spec); err != nil {
		return err
	}
	return sch.ValidateDatasource(plugin, name)
}

func validateDashboardSpec(spec modelV1.DashboardSpec, sch schema.Schema) error {
	if err := validateVariableNames(spec.Variables); err != nil {
		return err
	}

	if sch != nil {
		if err := sch.ValidateDashboardVariables(spec.Variables); err != nil {
			return err
		}
		if err := sch.ValidatePanels(spec.Panels); err != nil {
			return err
		}
	}
	if len(spec.Datasources) > 0 {
		defaultDts := make(map[string]bool)
		for dtsName, dtsSpec := range spec.Datasources {
			if err := validateDatasourcePlugin(dtsSpec.Plugin, dtsName, sch); err != nil {
				return err
			}
			if dtsSpec.Default {
				if defaultDts[dtsSpec.Plugin.Kind] {
					return fmt.Errorf("%s can not be defined as default datasource: there is already a default defined for kind %q", dtsName, dtsSpec.Plugin.Kind)
				}
				defaultDts[dtsSpec.Plugin.Kind] = true
			}
		}
	}
	return nil
}
