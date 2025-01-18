package system

type System interface {
	IsNixOS() bool
}
