package cmd

type MainOpts struct {
	ColorAlways  bool
	ConfigValues map[string]string
}

type AliasesOpts struct {
	DisplayJson bool
}

type ApplyOpts struct {
	Dry                   bool
	InstallBootloader     bool
	NoActivate            bool
	NoBoot                bool
	OutputPath            string
	ProfileName           string
	Specialisation        string
	GenerationTag         string
	UseNom                bool
	Verbosity             []bool
	BuildVM               bool
	BuildVMWithBootloader bool
	AlwaysConfirm         bool
	FlakeRef              string

	NixOptions struct {
		Quiet          bool
		PrintBuildLogs bool
		NoBuildOutput  bool
		ShowTrace      bool
		KeepGoing      bool
		KeepFailed     bool
		Fallback       bool
		Refresh        bool
		Repair         bool
		Impure         bool
		Offline        bool
		NoNet          bool
		MaxJobs        int
		Cores          int
		Builders       []string
		LogFormat      string
		Options        map[string]string

		RecreateLockFile bool
		NoUpdateLockFile bool
		NoWriteLockFile  bool
		NoUseRegistries  bool
		CommitLockFile   bool
		UpdateInputs     []string
		OverrideInputs   map[string]string
	}
}

type EnterOpts struct {
	Command      string
	CommandArray []string
	RootLocation string
	System       string
	Silent       bool
	Verbose      bool
}

type FeaturesOpts struct {
	DisplayJson bool
}
