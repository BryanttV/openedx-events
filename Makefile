.PHONY: clean clean_tox compile_translations coverage diff_cover docs dummy_translations \
        extract_translations fake_translations help pull_translations push_translations \
        quality requirements selfcheck test test-all upgrade validate install_transifex_client

.DEFAULT_GOAL := help

# For opening files in a browser. Use like: $(BROWSER)relative/path/to/file.html
BROWSER := python -m webbrowser file://$(CURDIR)/

help: ## display this help message
	@echo "Please use \`make <target>' where <target> is one of"
	@awk -F ':.*?## ' '/^[a-zA-Z]/ && NF==2 {printf "\033[36m  %-25s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST) | sort

clean: ## remove generated byte code, coverage reports, and build artifacts
	find . -name '__pycache__' -exec rm -rf {} +
	find . -name '*.pyc' -exec rm -f {} +
	find . -name '*.pyo' -exec rm -f {} +
	find . -name '*~' -exec rm -f {} +
	coverage erase
	rm -fr build/
	rm -fr dist/
	rm -fr *.egg-info

clean_tox: ## clear tox requirements cache
	rm -fr .tox

coverage: clean ## generate and view HTML coverage report
	pytest --cov-report html
	$(BROWSER)htmlcov/index.html

docs: ## generate Sphinx HTML documentation, including API docs
	tox -e docs
	$(BROWSER)docs/_build/html/index.html

changelog-entry: ## Create a new changelog entry
	scriv create

changelog: ## Collect changelog entries in the CHANGELOG.md file
	scriv collect

# Define PIP_COMPILE_OPTS=-v to get more information during make upgrade.
PIP_COMPILE = pip-compile --upgrade $(PIP_COMPILE_OPTS)

upgrade: export CUSTOM_COMPILE_COMMAND=make upgrade
upgrade: ## update the requirements/*.txt files with the latest packages satisfying requirements/*.in
	pip install -qr requirements/pip-tools.txt
	# Make sure to compile files after any other files they include!
	$(PIP_COMPILE) --allow-unsafe -o requirements/pip.txt requirements/pip.in
	$(PIP_COMPILE) -o requirements/pip-tools.txt requirements/pip-tools.in
	pip install -qr requirements/pip.txt
	pip install -qr requirements/pip-tools.txt
	$(PIP_COMPILE) -o requirements/base.txt requirements/base.in
	$(PIP_COMPILE) -o requirements/test.txt requirements/test.in
	$(PIP_COMPILE) -o requirements/doc.txt requirements/doc.in
	$(PIP_COMPILE) -o requirements/quality.txt requirements/quality.in
	$(PIP_COMPILE) -o requirements/ci.txt requirements/ci.in
	$(PIP_COMPILE) -o requirements/dev.txt requirements/dev.in
	# Let tox control the Django version for tests
	sed '/^[dD]jango==/d' requirements/test.txt > requirements/test.tmp
	mv requirements/test.tmp requirements/test.txt

quality: ## check coding style with pycodestyle and pylint
	tox -e quality

piptools: ## install pinned version of pip-compile and pip-sync
	pip install -r requirements/pip.txt
	pip install -r requirements/pip-tools.txt

requirements: clean_tox piptools ## install development environment requirements
	pip-sync -q requirements/dev.txt requirements/private.*

test: clean ## run tests in the current virtualenv
	pytest

diff_cover: test ## find diff lines that need test coverage
	diff-cover coverage.xml

test-all: quality ## run tests on every supported Python/Django combination
	tox
	tox -e docs

validate: quality test ## run tests and quality checks

isort:  ## fix improperly sorted imports
	isort test_utils openedx_events manage.py setup.py

selfcheck: ## check that the Makefile is well-formed
	@echo "The Makefile is well-formed."

## Localization targets

extract_translations: ## extract strings to be translated, outputting .mo files
	rm -rf docs/_build
	cd {{cookiecutter.app_name}} && i18n_tool extract --no-segment

compile_translations: ## compile translation files, outputting .po files for each supported language
	cd {{cookiecutter.app_name}} && i18n_tool generate

detect_changed_source_translations:
	cd {{cookiecutter.app_name}} && i18n_tool changed

ifeq ($(OPENEDX_ATLAS_PULL),)
pull_translations: ## Pull translations from Transifex
	tx pull -t -a -f --mode reviewed --minimum-perc=1
else
# Experimental: OEP-58 Pulls translations using atlas
pull_translations:
	find {{cookiecutter.app_name}}/conf/locale -mindepth 1 -maxdepth 1 -type d -exec rm -r {} \;
	atlas pull $(OPENEDX_ATLAS_ARGS) translations/{{cookiecutter.repo_name}}/{{cookiecutter.app_name}}/conf/locale:{{cookiecutter.app_name}}/conf/locale
	python manage.py compilemessages

	@echo "Translations have been pulled via Atlas and compiled."
endif

push_translations: ## push source translation files (.po) from Transifex
	tx push -s

dummy_translations: ## generate dummy translation (.po) files
	cd {{cookiecutter.app_name}} && i18n_tool dummy

build_dummy_translations: extract_translations dummy_translations compile_translations ## generate and compile dummy translation files

validate_translations: build_dummy_translations detect_changed_source_translations ## validate translations

install_transifex_client: ## Install the Transifex client
	# Instaling client will skip CHANGELOG and LICENSE files from git changes
	# so remind the user to commit the change first before installing client.
	git diff -s --exit-code HEAD || { echo "Please commit changes first."; exit 1; }
	curl -o- https://raw.githubusercontent.com/transifex/cli/master/install.sh | bash
	git checkout -- LICENSE README.md ## overwritten by Transifex installer
