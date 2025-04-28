package settings

import "context"

type settincsCtxKeyType string

const settingsCtxKey settincsCtxKeyType = "settings"

func WithConfig(ctx context.Context, cfg *Settings) context.Context {
	return context.WithValue(ctx, settingsCtxKey, cfg)
}

func FromContext(ctx context.Context) *Settings {
	logger, ok := ctx.Value(settingsCtxKey).(*Settings)
	if !ok {
		panic("settings not present in context")
	}
	return logger
}
