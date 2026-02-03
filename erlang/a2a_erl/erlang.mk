# Erlang.mk - A build tool for Erlang/OTP projects
# This is a bootstrap script that will download the actual erlang.mk

.PHONY: bootstrap erlang.mk

bootstrap:
	@echo "Bootstrapping erlang.mk..."
	@mkdir -p .erlang.mk.build
	@cd .erlang.mk.build && git clone --depth 1 https://github.com/ninenines/erlang.mk .
	@cd .erlang.mk.build && $(MAKE)
	@cp .erlang.mk.build/erlang.mk ./erlang.mk
	@rm -rf .erlang.mk.build

erlang.mk: bootstrap
	@echo "erlang.mk ready!"