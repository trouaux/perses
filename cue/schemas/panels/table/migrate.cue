if (*#panel.type | null) == "table" {
	kind: "Table"
	spec: {
		#cellHeight: *#panel.options.cellHeight | null
		if #cellHeight != null {
			density: [
				if #cellHeight == "sm" {"compact"},
				if #cellHeight == "lg" {"comfortable"},
				"standard",
			][0]
		}

		// Logic to build columnSettings:

		_nameBuilder: {
			#var: string
			output: [
				// Rename anonymous fields that Perses names differently than Grafana
				if #var == "Time" { "timestamp" },
				if #var == "Value" { "value" },
				#var
			][0]
		}

		// Function-pattern to gather all values associated to the given name & attribute.
		// It goes through both transformations and field overrides to gather the values.
		_gatherSetting: {
			name: string
			keyInTransformations: string
			propertyInFieldOverrides: string
			
			return: list.Concat([
				[if keyInTransformations != _|_ 
					for transformation in (*#panel.transformations | [])
						if transformation.id == "organize"
							for columnName, value in (*transformation.options[keyInTransformations] | {})
								if columnName == name {
									value
								}
				],
				[if propertyInFieldOverrides != _|_
					for override in (*#panel.fieldConfig.overrides | [])
						if override.matcher.id == "byName" && (*override.matcher.options | null) == name
							for property in override.properties
								if property.id == propertyInFieldOverrides {
									property.value
								}
				]
			])
		}

		// Function-pattern to gather all values associated to the given name for all the attributes
		_gatherSettings: {
			_name=name: string
			adjustedName: {_nameBuilder & {#var: name}}.output
			
			return: "\(adjustedName)": {
				headers: {_gatherSetting & { name: _name, keyInTransformations: "renameByName", propertyInFieldOverrides: "displayName"}}.return
				widths: {_gatherSetting & { name: _name, propertyInFieldOverrides: "custom.width"}}.return
				excludes: {_gatherSetting & { name: _name, keyInTransformations: "excludeByName"}}.return
			}
		}

		// We have to call the same logic multiple times, one time for each potential source of settings,
		// in order to not miss any value.
		_gatherer: {
			for transformation in (*#panel.transformations | [])
				if transformation.id == "organize"
					for columnName, _ in (*transformation.options.renameByName | {}) {
						{_gatherSettings & {name: columnName}}.return
					}
		}
		_gatherer: {
			for transformation in (*#panel.transformations | [])
				if transformation.id == "organize"
					for columnName, _ in (*transformation.options.excludeByName | {}) {
						{_gatherSettings & {name: columnName}}.return
					}
		}
		_gatherer: {
			for override in (*#panel.fieldConfig.overrides | [])
				if override.matcher.id == "byName" && override.matcher.options != _|_ {
					{_gatherSettings & {name: override.matcher.options}}.return
				}
		}

		columnSettings: [for columnName, settings in _gatherer {
			name: columnName
			// Why do we take the last elements in the cases below: it's mostly based on grafana's behavior
			// - field overrides take precedence over the organize transformation (organize transformation was processed first above)
			// - if there are multiple overrides for the same field, the last one takes precedence
			if len(settings.headers) > 0 {
				header: settings.headers[len(settings.headers) - 1]
			}
			if len(settings.excludes) > 0 {
				hide: settings.excludes[len(settings.excludes) - 1]
			}
			if len(settings.widths) > 0 {
				width: settings.widths[len(settings.widths) - 1]
			}
		}]

		// Logic to build cellSettings:

		// Using flatten to avoid having an array of arrays with "value" mappings
		// (https://cuelang.org/docs/howto/use-list-flattenn-to-flatten-lists/)
		let x = list.FlattenN([
			if (*#panel.fieldConfig.defaults.mappings | null) != null for mapping in #panel.fieldConfig.defaults.mappings {
				if mapping.type == "value" {
					[for key, option in mapping.options {
						condition: {
							kind: "Value"
							spec: {
								value: key
							}
						}
						if option.text != _|_ {
							text: option.text
						}
						if option.color != _|_ {
							backgroundColor: *#mapping.color[option.color] | option.color
						}
					}]
				}

				if mapping.type == "range" || mapping.type == "regex" || mapping.type == "special" {
					condition: [//switch
						if mapping.type == "range" {
							kind: "Range",
							spec: {
								if mapping.options.from != _|_ {
									min: mapping.options.from
								}
								if mapping.options.to != _|_ {
									max: mapping.options.to
								}
							}
						},
						if mapping.type == "regex" {
							kind: "Regex",
							spec: {
								expr: mapping.options.pattern
							}
						},
						if mapping.type == "special" {
							kind: "Misc",
							spec: {
								value: [//switch
									if mapping.options.match == "nan" {"NaN"},
									if mapping.options.match == "null+nan" {"null"},
									mapping.options.match,
								][0]
							}
						},
					][0]

					if mapping.options.result.text != _|_ {
						text: mapping.options.result.text
					}
					if mapping.options.result.color != _|_ {
						backgroundColor: *#mapping.color[mapping.options.result.color] | mapping.options.result.color
					}
				}
			},
		], 1)

		if len(x) > 0 {
			cellSettings: x
		}

		// Logic to build transforms:

		if #panel.transformations != _|_ {
			#transforms: [
				for transformation in #panel.transformations if transformation.id == "merge" || transformation.id == "joinByField" {
					if transformation.id == "merge" {
						kind: "MergeSeries"
						spec: {
							if transformation.disabled != _|_ {
								disabled: transformation.disabled
							}
						}
					}
					if transformation.id == "joinByField" {
						kind: "JoinByColumnValue"
						spec: {
							columns: *transformation.options.byField | []
							if transformation.disabled != _|_ {
								disabled: transformation.disabled
							}
						}
					}
				},
			]
			if len(#transforms) > 0 {
				transforms: #transforms
			}
		}
	}
},
if (*#panel.type | null) == "table-old" {
	kind: "Table"
	spec: {
		if #panel.styles != _|_ {
			columnSettings: [for style in #panel.styles {
				name: style.pattern
				if style.type == "hidden" {
					hide: true
				}
				if style.alias != _|_ {
					header: style.alias
				}
				#align: *style.align | "auto"
				if #align != "auto" {
					align: style.align
				}
			}]
		}
	}
},
