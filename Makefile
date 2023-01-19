
all_lib_files := $(shell fd .nix ./lib -x printf "%q\n")
all_doc_files = $(all_lib_files:%.nix=docs/gen/%.md)


default:
	@echo "Please choose one of the following targets:"
	@echo ""
	@echo "	docs, clean"
	@echo
	@exit 2


docs: nixtract pandoc $(all_doc_files)

.PHONY: clean
clean:
	rm $(all_doc_files)





# Impl
docs/gen/%.md: %.nix
	mkdir -p "$(shell dirname "$@")"
	nixtract "$<" \
	| pandoc -f json -t gfm -o "$@"


nixtract:
	@nixtract --version

pandoc:
	@pandoc --version
