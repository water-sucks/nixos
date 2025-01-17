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
	Verbose               bool
	BuildVM               bool
	BuildVMWithBootloader bool
	AlwaysConfirm         bool
	FlakeRef              string

	NixOptions ApplyNixOptions
}

type ApplyNixOptions struct {
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

type GenerationOpts struct {
	ProfileName string
}

type GenerationDiffOpts struct {
	Before uint
	After  uint
}

type GenerationDeleteOpts struct {
	All           bool
	LowerBound    uint
	Keep          []uint
	MinimumToKeep uint
	OlderThan     string
	UpperBound    uint
	AlwaysConfirm bool
	Delete        []uint
}

type GenerationListOpts struct {
	Interactive bool
	DisplayJson bool
}

type GenerationSwitchOpts struct {
	Dry            bool
	Specialisation string
	Verbose        bool
	AlwaysConfirm  bool
	Generation     uint
}

type GenerationRollbackOpts struct {
	Dry            bool
	Specialisation string
	Verbose        bool
	AlwaysConfirm  bool
}

type InfoOpts struct {
	DisplayJson     bool
	DisplayMarkdown bool
}

type InitOpts struct {
	Directory          string
	ForceWrite         bool
	NoFSGeneration     bool
	Root               string
	ShowHardwareConfig bool
}

type InstallOpts struct {
	Channel        string
	NoBootloader   bool
	NoChannelCopy  bool
	NoRootPassword bool
	Root           string
	SystemClosure  string
	Verbose        bool
	FlakeRef       string

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

type OptionOpts struct {
	Interactive      bool
	NixPathIncludes  []string
	DisplayJson      bool
	NoUseCache       bool
	DisplayValueOnly bool
	OptionInput      string
}

type ReplOpts struct {
	NixPathIncludes []string
	FlakeRef        string
}
