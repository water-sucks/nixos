package buildOpts

// Do not change these. These are always going to be set
// at compile-time.

var (
	Version        string = "unknown"
	GitRevision    string = "unknown"
	Flake          string = "true"
	NixpkgsVersion string = ""
)

func boolCheck(varName string, value string) {
	if value != "true" && value != "false" {
		panic("Compile-time variable internal.build." + varName + " is not a value of either 'true' or 'false'; this application was compiled incorrectly")
	}
}

func init() {
	boolCheck("Flake", Flake)
}
