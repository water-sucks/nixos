package errors

type ArgError struct {
	Message string
	Hint    string
}

func (e ArgError) Error() string {
	return e.Message
}
