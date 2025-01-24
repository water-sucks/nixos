package generation

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"time"

	"github.com/djherbis/times"
	"github.com/water-sucks/nixos/internal/constants"
	"github.com/water-sucks/nixos/internal/logger"
)

func GetProfileDirectoryFromName(profile string) string {
	if profile != "system" {
		return filepath.Join(constants.NixSystemProfileDirectory, profile)
	} else {
		return filepath.Join(constants.NixProfileDirectory, "system")
	}
}

type Generation struct {
	Number          uint64
	CreationDate    time.Time
	IsCurrent       bool
	KernelVersion   string
	Specialisations []string

	NixosVersion          string
	NixpkgsRevision       string
	ConfigurationRevision string
	Description           string
}

type GenerationManifest struct {
	NixosVersion          string `json:"nixosVersion"`
	NixpkgsRevision       string `json:"nixpkgsRevision"`
	ConfigurationRevision string `json:"configurationRevision"`
	Description           string `json:"description"`
}

type GenerationReadError struct {
	Profile string
	Number  uint64
	Errors  []error
}

func (e *GenerationReadError) Error() string {
	return fmt.Sprintf("failed to read generation %d from profile %s", e.Number, e.Profile)
}

func GenerationFromDirectory(profile string, number uint64) (*Generation, error) {
	profileDirectory := constants.NixProfileDirectory
	if profile != "system" {
		profileDirectory = constants.NixSystemProfileDirectory
	}

	generationDirectoryName := filepath.Join(profileDirectory, fmt.Sprintf("%s-%d-link", profile, number))
	nixosVersionManifestFile := filepath.Join(generationDirectoryName, "nixos-version.json")

	if _, err := os.Stat(generationDirectoryName); err != nil {
		return nil, err
	}

	info := &Generation{
		Number:          number,
		CreationDate:    time.Time{},
		IsCurrent:       false,
		KernelVersion:   "",
		Specialisations: []string{},
	}

	encounteredErrors := []error{}

	manifestBytes, err := os.ReadFile(nixosVersionManifestFile)
	if err != nil {
		encounteredErrors = append(encounteredErrors, err)
	} else {
		var manifest GenerationManifest
		err := json.Unmarshal(manifestBytes, &manifest)

		if err != nil {
			encounteredErrors = append(encounteredErrors, err)
		} else {
			info.NixosVersion = manifest.NixosVersion
			info.NixpkgsRevision = manifest.NixpkgsRevision
			info.ConfigurationRevision = manifest.ConfigurationRevision
			info.Description = manifest.Description
		}
	}

	// Fall back to reading the nixos-version file that should always
	// exist if the version doesn't.
	if info.NixosVersion == "" {
		nixosVersionFile := filepath.Join(generationDirectoryName, "nixos-version")
		nixosVersionContents, err := os.ReadFile(nixosVersionFile)
		if err != nil {
			encounteredErrors = append(encounteredErrors, err)
		} else {
			info.NixosVersion = string(nixosVersionContents)
		}
	}

	// Get time of creation for the generation
	creationTimeStat, err := times.Stat(generationDirectoryName)
	if err != nil {
		encounteredErrors = append(encounteredErrors, err)
	} else {
		if creationTimeStat.HasBirthTime() {
			info.CreationDate = creationTimeStat.BirthTime()
		} else {
			info.CreationDate = creationTimeStat.ModTime()
		}
	}

	kernelVersionDirGlob := filepath.Join(generationDirectoryName, "kernel-modules", "lib", "modules", "*")
	kernelVersionMatches, err := filepath.Glob(kernelVersionDirGlob)
	if err != nil {
		encounteredErrors = append(encounteredErrors, err)
	} else if len(kernelVersionMatches) == 0 {
		encounteredErrors = append(encounteredErrors, fmt.Errorf("no kernel modules version directory found"))
	} else {
		info.KernelVersion = filepath.Base(kernelVersionMatches[0])
	}

	specialisations := []string{}
	specialisationsGlob := filepath.Join(generationDirectoryName, "specialisation", "*")
	specialisationsMatches, err := filepath.Glob(specialisationsGlob)
	if err != nil {
		encounteredErrors = append(encounteredErrors, err)
	} else {
		for _, match := range specialisationsMatches {
			specialisations = append(specialisations, filepath.Base(match))
		}
	}
	info.Specialisations = specialisations

	sort.Strings(info.Specialisations)

	if len(encounteredErrors) > 0 {
		return info, &GenerationReadError{
			Profile: profile,
			Number:  number,
			Errors:  encounteredErrors,
		}
	}

	return info, nil
}

func CollectGenerationsInProfile(log *logger.Logger, profile string) ([]Generation, error) {
	profileDirectory := constants.NixProfileDirectory
	if profile != "system" {
		profileDirectory = constants.NixSystemProfileDirectory
	}

	generationDirEntries, err := os.ReadDir(profileDirectory)
	if err != nil {
		return nil, err
	}

	genDirRegex, err := regexp.Compile(fmt.Sprintf(`^%s-(\d+)-link$`, profile))
	if err != nil {
		return nil, fmt.Errorf("failed to compile generation regex: %w", err)
	}

	currentGenerationDirname := GetProfileDirectoryFromName(profile)
	currentGenerationLink, err := os.Readlink(currentGenerationDirname)
	if err != nil {
		log.Warnf("unable to determine current generation: %v", err)
	}

	generations := []Generation{}
	for _, v := range generationDirEntries {
		name := v.Name()

		if matches := genDirRegex.FindStringSubmatch(name); len(matches) > 0 {
			genNumber, err := strconv.ParseInt(matches[1], 10, 64)
			if err != nil {
				log.Warnf("failed to parse generation number %v for %v, skipping", matches[1], filepath.Join(profileDirectory, name))
				continue
			}

			info, err := GenerationFromDirectory(profile, uint64(genNumber))
			if err != nil {
				return nil, err
			}

			if name == currentGenerationLink {
				info.IsCurrent = true
			}

			generations = append(generations, *info)
		}
	}

	sort.Slice(generations, func(i, j int) bool {
		return generations[i].Number > generations[j].Number
	})

	return generations, nil
}
