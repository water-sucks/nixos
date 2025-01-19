package nixopts

import (
	"fmt"
	"reflect"
	"sort"
)

var availableOptions = map[string]string{
	"Quiet":            "quiet",
	"PrintBuildLogs":   "print-build-logs",
	"NoBuildOutput":    "fallback",
	"ShowTrace":        "show-trace",
	"KeepGoing":        "keep-going",
	"KeepFailed":       "keep-failed",
	"Fallback":         "fallback",
	"Refresh":          "refresh",
	"Repair":           "repair",
	"Impure":           "impure",
	"Offline":          "offline",
	"NoNet":            "no-net",
	"MaxJobs":          "max-jobs",
	"Cores":            "cores",
	"LogFormat":        "log-format",
	"Options":          "option",
	"Builders":         "builders",
	"RecreateLockFile": "recreate-lock-file",
	"NoUpdateLockFile": "no-update-lock-file",
	"NoWriteLockFile":  "no-write-lock-file",
	"NoUseRegistries":  "no-use-registries",
	"CommitLockFile":   "commit-lock-file",
	"UpdateInputs":     "update-inputs",
	"OverrideInputs":   "override-input",
}

func getNixFlag(name string) string {
	if option, ok := availableOptions[name]; ok {
		return option
	}

	panic("unknown option '" + name + "' when trying to convert to nix options struct")
}

func NixOptionsToArgsList(options interface{}) []string {
	val := reflect.ValueOf(options)
	typ := reflect.TypeOf(options)

	if val.Kind() == reflect.Ptr {
		val = val.Elem()
		typ = typ.Elem()
	}

	args := make([]string, 0)

	for i := 0; i < val.NumField(); i++ {
		field := val.Field(i)
		fieldType := typ.Field(i)
		fieldName := getNixFlag(fieldType.Name)

		optionArg := fmt.Sprintf("--%s", fieldName)

		switch field.Kind() {
		case reflect.Bool:
			if field.Bool() {
				args = append(args, optionArg)
			}
		// TODO: Differentiate between zero values and empty zero
		case reflect.Int:
			if field.Int() != 0 {
				args = append(args, optionArg, fmt.Sprintf("%d", field.Int()))
			}
		case reflect.String:
			if field.String() != "" {
				args = append(args, optionArg, field.String())
			}
		case reflect.Slice:
			if field.Len() > 0 {
				for j := 0; j < field.Len(); j++ {
					args = append(args, optionArg, field.Index(j).String())
				}
			}
		case reflect.Map:
			keys := field.MapKeys()

			sort.Slice(keys, func(i, j int) bool {
				return keys[i].String() < keys[j].String()
			})

			for _, key := range keys {
				value := field.MapIndex(key)
				args = append(args, optionArg, key.String(), value.String())
			}
		default:
			panic("unsupported field type " + field.Kind().String() + " for field '" + fieldName + "'")
		}
	}

	return args
}
