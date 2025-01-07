package config

import "context"

type configCtxKeyType string

const configCtxKey configCtxKeyType = "config"

func WithConfig(ctx context.Context, cfg *Config) context.Context {
	return context.WithValue(ctx, configCtxKey, cfg)
}

func FromContext(ctx context.Context) *Config {
	logger, ok := ctx.Value(configCtxKey).(*Config)
	if !ok {
		panic("config not present in context")
	}
	return logger
}
