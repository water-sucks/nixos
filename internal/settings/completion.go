package settings

import (
	"fmt"
	"reflect"
	"strings"

	"github.com/spf13/cobra"
)

type fieldCompleteResult struct {
	Name        string
	Description string
}

func findFieldCompletions(value any, prefix string) ([]fieldCompleteResult, bool) {
	var candidates []fieldCompleteResult

	fieldNames := strings.Split(prefix, ".")

	finalFieldComponent := ""
	previousComponents := []string{}

	if len(fieldNames) > 0 {
		finalFieldComponent = fieldNames[len(fieldNames)-1]
		previousComponents = fieldNames[:len(fieldNames)-1]
	}

	current := reflect.ValueOf(value)

	if current.Kind() == reflect.Ptr {
		current = current.Elem()
	}

	for i, fieldName := range fieldNames {
		if i == len(fieldNames)-1 {
			break
		}

		found := false
		for j := 0; j < current.Type().NumField(); j++ {
			fieldInfo := current.Type().Field(j)
			if fieldInfo.Tag.Get("koanf") == fieldName {
				current = current.Field(j)
				found = true
				break
			}
		}

		if !found {
			return []fieldCompleteResult{}, false
		}
	}

	if current.Kind() == reflect.Ptr {
		if current.IsNil() {
			current.Set(reflect.New(current.Type().Elem()))
		}
		current = current.Elem()
	}

	if current.Kind() != reflect.Struct {
		return []fieldCompleteResult{}, false
	}

	for i := 0; i < current.Type().NumField(); i++ {
		structField := current.Type().Field(i)

		if skip := structField.Tag.Get("noset"); skip == "true" {
			continue
		}

		name := structField.Tag.Get("koanf")
		description := structField.Tag.Get("description")

		if name == finalFieldComponent {
			field := current.Field(i)
			isComplete := isSettable(&field)

			completeCandidate := strings.Join(append(previousComponents, name), ".")

			result := fieldCompleteResult{
				Name:        completeCandidate,
				Description: description,
			}

			return []fieldCompleteResult{result}, isComplete
		}

		if strings.HasPrefix(name, finalFieldComponent) {
			candidates = append(candidates, fieldCompleteResult{
				Name:        name,
				Description: description,
			})
		}
	}

	isComplete := false
	if len(candidates) == 1 {
		candidate := candidates[0].Name

		var autocompleted string = ""

		for i := 0; i < current.Type().NumField(); i++ {
			structField := current.Type().Field(i)

			name := structField.Tag.Get("koanf")

			if strings.HasPrefix(name, candidate) {
				autocompleted = name
				field := current.Field(i)
				isComplete = isSettable(&field)
				break
			}
		}

		if autocompleted != "" {
			candidates[0].Name = autocompleted
		} else {
			panic("no autocompleted result for name " + candidate + " when there should be one")
		}
	}

	for i, v := range candidates {
		candidates[i].Name = strings.Join(append(previousComponents, v.Name), ".")
	}

	return candidates, isComplete
}

func CompleteConfigFlag(_ *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
	splitIndex := strings.Index(toComplete, "=")
	if splitIndex == -1 {
		return completeKeys(toComplete)
	}

	key := toComplete[0:splitIndex]
	candidate := toComplete[splitIndex+1:]

	return completeValues(key, candidate)
}

func completeKeys(candidate string) ([]string, cobra.ShellCompDirective) {
	completionCandidates, complete := findFieldCompletions(NewSettings(), candidate)

	// There are three cases of completions where extra actions need to be taken:
	// 1. Multiple candidates remaining
	//    - Do nothing
	// 2. Single candidate, but does not represent a settable key (aka a struct)
	//    - Add a '.', more input is needed
	// 3. Single candidate, and complete key is found
	//    - Add a '=' to signify start of value completions, if they exist
	if len(completionCandidates) == 1 {
		if complete {
			completionCandidates[0].Name = completionCandidates[0].Name + "="
		} else {
			completionCandidates[0].Name = completionCandidates[0].Name + "."
		}
	}

	candidates := make([]string, len(completionCandidates))
	for i, v := range completionCandidates {
		if v.Description != "" {
			candidates[i] = fmt.Sprintf("%v\t%v", v.Name, v.Description)
		} else {
			candidates[i] = v.Name
		}
	}

	// Completion of keys should never end with a space, since the value
	// is required.
	return candidates, cobra.ShellCompDirectiveNoSpace
}

type CompletionValueFunc func(key string, candidate string) ([]string, cobra.ShellCompDirective)

func boolCompletionFunc(key string, candidate string) ([]string, cobra.ShellCompDirective) {
	options := []string{"true\tTurn this setting on", "false\tTurn this setting off"}
	var matches []string

	for _, option := range options {
		if strings.HasPrefix(option, candidate) {
			// Yeah, this kind of sucks. It would be preferable to not have to include
			// the prefix in the arguments, since this becomes rather verbose,
			// but this works alright, for now.

			match := fmt.Sprintf("%v=%v", key, option)
			matches = append(matches, match)
		}
	}

	return matches, cobra.ShellCompDirectiveNoFileComp
}

var completionValueFuncs = map[string]CompletionValueFunc{
	"apply.imply_impure_with_tag": boolCompletionFunc,
	"apply.use_nom":               boolCompletionFunc,
	"apply.use_git_commit_msg":    boolCompletionFunc,
	"color":                       boolCompletionFunc,
	"use_nvd":                     boolCompletionFunc,
}

func completeValues(key string, value string) ([]string, cobra.ShellCompDirective) {
	if completeFunc, ok := completionValueFuncs[key]; ok {
		return completeFunc(key, value)
	}

	return []string{}, cobra.ShellCompDirectiveDefault
}
