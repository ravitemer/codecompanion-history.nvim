all: format test docs

format:
	@echo Formatting...
	@stylua tests/ lua/ -f ./stylua.toml

test: deps
	@echo Testing...
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

test_file: deps
	@echo Testing File...
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

docs: deps/panvimdoc
	@echo Generating Docs...
	@cd deps/panvimdoc && \
	pandoc \
		--metadata="project:codecompanion-history" \
		--metadata="vimversion:NVIM v0.8.0" \
		--metadata="titledatepattern:%Y %B %d" \
		--metadata="toc:true" \
		--metadata="incrementheadinglevelby:0" \
		--metadata="treesitter:true" \
		--metadata="dedupsubheadings:true" \
		--metadata="ignorerawblocks:true" \
		--metadata="docmapping:false" \
		--metadata="docmappingproject:true" \
		--lua-filter scripts/include-files.lua \
		--lua-filter scripts/skip-blocks.lua \
		--lua-filter scripts/remove-emojis.lua \
		-t scripts/panvimdoc.lua \
		../../README.md \
		-o ../../doc/codecompanion-history.txt

deps: deps/plenary.nvim deps/codecompanion.nvim deps/nvim-treesitter deps/mini.nvim deps/panvimdoc
	@echo Pulling...

deps/plenary.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/nvim-lua/plenary.nvim.git $@

# Get latest codecompanion.nvim every hour (useful while developing)
deps/codecompanion.nvim:
	@mkdir -p deps
	@if [ ! -f deps/.codecompanion-timestamp ] || [ $$(find deps/.codecompanion-timestamp -mmin +60 2>/dev/null) ]; then \
		echo "Updating codecompanion..."; \
		rm -rf "$@"; \
		git clone --filter=blob:none https://github.com/olimorris/codecompanion.nvim.git $@; \
		touch deps/.codecompanion-timestamp; \
		else \
		echo "Codecompanion is up to date"; \
		fi

.PHONY: force-update-codecompanion deps/codecompanion.nvim

force-update-codecompanion:
	@rm -f deps/.codecompanion-timestamp
	@make deps/codecompanion.nvim

deps/nvim-treesitter:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/nvim-treesitter/nvim-treesitter.git $@

deps/mini.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/echasnovski/mini.nvim $@

deps/panvimdoc:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/kdheepak/panvimdoc $@
