LibraryVersion:=0.0.28
NugetApiKey:=

source:=
target:=

lang:=

proto_root:=proto
templates_root:=templates

scratch:=scratch
copy_target_root:=$(scratch)/build/templates

test_install_root:=$(scratch)/test
scratch_proj:=neptune

ifeq ($(lang),csharp)
projsuffix=csproj
language=C\#
language_name=CSharp
else
projsuffix=fsproj
language=F\#
language_name=FSharp
endif

template-types:=dotnet-webapi orleans-directclient
languages:=csharp fsharp

devenv-image:=westisland/tugboat:latest

# Docker Targets
docker-stop :
	@echo Stopping all  containers
	- docker stop $(shell docker ps -aq)

docker-kill : docker-stop
	@echo Killing and removing all containers
	- docker rm -f $(shell docker ps -aq)
	- docker kill  $(shell docker ps -aq)

docker-clean : docker-kill
	@echo Pruning all images
	- docker image prune -af

# Utility Targets
copy:
	mkdir -p $(target)
# Support BSDTAR which is now native on Windows 10, and which is preferred on Windows even though it is unable to do piping! :-/
# http://gnuwin32.sourceforge.net/packages/gtar.htm
	tar -c --exclude bin --exclude obj --exclude .vs --exclude Properties --exclude *.user -f $(target).tar $(source)
	tar -x --strip-components=3 -C $(target) -f $(target).tar
	- rm -f $(target).tar

replace-pattern :
ifneq ("$(wildcard $(copy_target_root)/$(template)-$(lang)/$(replace_in_file))", "")
	sed -e "s/$(replace_pattern)/$(replacement_pattern)/g" $(copy_target_root)/$(template)-$(lang)/$(replace_in_file) > $(copy_target_root)/$(template)-$(lang)/$(replace_in_file).tmp
	mv $(copy_target_root)/$(template)-$(lang)/$(replace_in_file).tmp $(copy_target_root)/$(template)-$(lang)/$(replace_in_file)
endif

pack :
	dotnet build -c Release $(project_path)
	dotnet pack  --no-build -c Release $(project_path) -p:PackageId=$(package_name) -p:PackageVersion=$(package_version) -o .
	@echo Built and Packed Library
	@echo

push :
	dotnet nuget push ./$(package_name).$(package_version).nupkg -s https://api.nuget.org/v3/index.json -k $(NugetApiKey)
	@echo Pushed Library to Nuget
	@echo

# Main Targets
setup-git-user :
	git config user.name  server
	git config user.email server@server.com
	@echo Done Setting Up Git User
	@echo

all : clean build setup-templates test-templates

clean : clean-packages clean-template-pack
	@echo Done cleaning
	@echo

build : dn-clean-project dn-restore-project dn-build-project dn-test-project
	@echo Done Building Projects
	@echo

dn-clean-project :
	- dotnet clean tugboat-dev.sln

dn-restore-project :
	dotnet restore --force tugboat-dev.sln

dn-build-project :
	dotnet build --no-restore tugboat-dev.sln

dn-test-project :
	dotnet test --no-build tugboat-dev.sln

setup-templates : clean-template-pack copy-template-pack pack-template-pack install-template-pack
	@echo Done Setting Up Templates
	@echo

# Library Targets
push-library : pack-library
	$(MAKE) package_name=WestIsland.Tugboat package_version=$(LibraryVersion) push

pack-library :
	$(MAKE) project_path=Library.Tugboat/Library.Tugboat.csproj package_name=WestIsland.Tugboat package_version=$(LibraryVersion) pack

# Clean Targets
clean-packages :
	- rm *.nupkg

clean-template-pack :
	- rm -rf $(scratch)

# Template Targets
push-template-pack : clean-template-pack copy-template-pack pack-template-pack
	$(MAKE) package_name=WestIsland.Tugboat.Templates package_version=$(LibraryVersion) push

# Template Copy Targets
copy-template-pack : $(foreach l,$(languages),$(foreach t,$(template-types),copy-template.$(t).$(l)))
	cp $(templates_root)/Tugboat.Templates.csproj $(scratch)/build
	@echo Copied Template Pack
	@echo

copy-template.% : lang=$(subst .,,$(suffix $*))
copy-template.% : template=$(basename $*)
copy-template.% :
	$(MAKE) lang=$(lang) template=$(template) copy-code-folder.$(template)
	$(MAKE) lang=$(lang) template=$(template) copy-templates.$(template)
	$(MAKE) lang=$(lang) template=$(template) copy-ignores.$(template)
	@echo Built Template Folder For $* [$(lang)]
	@echo

copy-code-folder.dotnet-webapi :
	$(MAKE) lang=$(lang) template=$(template) copy-template-subfolder.appl
	$(MAKE) lang=$(lang) template=$(template) copy-template-subfolder.appl-controllers
	$(MAKE) lang=$(lang) template=$(template) copy-template-subfolder.appl-logic
	$(MAKE) lang=$(lang) template=$(template) copy-template-subfolder.appl-tests
	@echo

copy-code-folder.orleans-directclient :
	$(MAKE) lang=$(lang) template=$(template) copy-template-subfolder.appl
	$(MAKE) lang=$(lang) template=$(template) copy-template-subfolder.grain-controllers
	$(MAKE) lang=$(lang) template=$(template) copy-template-subfolder.grains
	$(MAKE) lang=$(lang) template=$(template) copy-template-subfolder.grain-tests
	@echo

copy-template-subfolder.% :
	@echo [$(lang)] Copying SubFolder [$*] for [$(template)]
	$(MAKE) source=$(proto_root)-$(lang)/$(template)/$* target=$(copy_target_root)/$(template)-$(lang)/src/$* copy
	$(MAKE) src_project_file=$(template)/$*/$*.$(projsuffix) dest_project_file=$(template)-$(lang)/src/$*/$*.$(projsuffix) replace-project-reference-with-nuget-reference
	@echo

copy-templates.% : makefiles=$(foreach f,$(wildcard .makefiles/*.Makefile),$(notdir $(f)))
copy-templates.% :
	@echo Copying Templates For $* [$(lang)]
	cp -rv $(templates_root)/$*/. $(copy_target_root)/$*-$(lang)
	@echo
	@echo Fixing up Language Specific Suffixes
	$(MAKE) replace_pattern=_PROJ_SUFFIX_ replacement_pattern=$(projsuffix) replace_in_file=Makefile    template=$* replace-pattern
	$(MAKE) replace_pattern=_PROJ_SUFFIX_ replacement_pattern=$(projsuffix) replace_in_file=Dockerfile  template=$* replace-pattern
	$(MAKE) replace_pattern=_PROJ_SUFFIX_ replacement_pattern=$(projsuffix) replace_in_file=appl.sln    template=$* replace-pattern
	$(MAKE) replace_pattern=_TEMPLATE_    replacement_pattern=$*            replace_in_file=README.md   template=$* replace-pattern
	mv $(copy_target_root)/$*-$(lang)/appl.sln $(copy_target_root)/$*-$(lang)/src/appl.sln

	$(MAKE) replace_pattern=_LANGNAME_ replacement_pattern=$(language_name) replace_in_file=.template.config/template.json template=$* replace-pattern
	$(MAKE) replace_pattern=_LANG_     replacement_pattern=$(language)      replace_in_file=.template.config/template.json template=$* replace-pattern

	for f in $(makefiles); do\
		$(MAKE) replace_pattern=_PROJ_SUFFIX_ replacement_pattern=$(projsuffix) replace_in_file=.makefiles/$$f template=$* replace-pattern;\
	done
	@echo

copy-ignores.% :
	@echo Copying .gitignore and .dockerignore For $* [$(lang)]
	- cp .gitignore    $(copy_target_root)/$*-$(lang)/.gitignore
	- cp .dockerignore $(copy_target_root)/$*-$(lang)/.dockerignore
	@echo

replace-project-reference-with-nuget-reference :
	- sed -e "s/<ProjectReference.*Library.Tugboat.csproj\"/<PackageReference Include=\"WestIsland.Tugboat\" Version=\"*\"/g" $(proto_root)-$(lang)/$*/$(src_project_file) > $(copy_target_root)/$(dest_project_file)

pack-template-pack :
	$(MAKE) project_path=$(scratch)/build/Tugboat.Templates.csproj package_name=WestIsland.Tugboat.Templates package_version=$(LibraryVersion) pack

uninstall-template-pack :
	- dotnet new -u WestIsland.Tugboat.Templates

install-template-pack : uninstall-template-pack
	dotnet new -i WestIsland.Tugboat.Templates.$(LibraryVersion).nupkg

# Template Test Targets
test-templates : $(foreach l,$(languages),$(foreach t,$(template-types),test-template.$(t).$(l)))
	@echo Completed Testing Templates
	@echo

test-template.% : lang=$(subst .,,$(suffix $*))
test-template.% : template=$(basename $*)
test-template.% :
	$(MAKE) lang=$(lang) template=$(template) test-scratch-project

test-scratch-project : create-scratch-project test-dotnet-flow test-docker-flow

test-docker-flow :
	$(MAKE) -C $(test_install_root)/$(lang)/$(template)/ docker-build

test-dotnet-flow :
	$(MAKE) -C $(test_install_root)/$(lang)/$(template)/ dotnet-build dotnet-test

create-scratch-project :
	mkdir -p $(test_install_root)
	dotnet new $(template) -lang $(language) -n $(scratch_proj) -o $(test_install_root)/$(lang)/$(template)

#devenv targets
devenv-image :
	- docker build -f DevEnvironment.Dockerfile -t $(devenv-image) .
#	- docker scan --accept-license -f DevEnvironment.Dockerfile $(devenv-image)

devenv-image-push: devenv-image
	docker login
	- docker push $(devenv-image)