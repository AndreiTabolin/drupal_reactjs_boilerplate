.PHONY: default pull up stop down restart \
exec exec\:wodby exec\:root drush composer \
prepare\:backend prepare\:frontend prepare\:platformsh \
install install\:platformsh update \
db\:dump db\:drop db\:import \
files\:sync files\:sync\:public files\:sync\:private \
code\:check code\:fix \
yarn logs \
tests\:prepare tests\:run tests\:cli tests\:autocomplete

# Create local environment files.
$(shell cp -n \.\/\.docker\/docker-compose\.override\.default\.yml \.\/\.docker\/docker-compose\.override\.yml)
$(shell cp -n \.env\.default \.env)
$(shell cp -n \.env\.default \.\/reactjs\/\.env)
include .env

# Define function to highlight messages.
# @see https://gist.github.com/leesei/136b522eb9bb96ba45bd
cyan = \033[38;5;6m
bold = \033[1m
reset = \033[0m
message = @echo "${cyan}${bold}${1}${reset}"

# Define 3 users with different permissions within the container.
# docker-www-data is applicable only for php container.
docker-www-data = docker-compose exec --user=82:82 $(firstword ${1}) time -f"%E" sh -c "$(filter-out $(firstword ${1}), ${1})"
docker-wodby = docker-compose exec $(firstword ${1}) time -f"%E" sh -c "$(filter-out $(firstword ${1}), ${1})"
docker-root = docker-compose exec --user=0:0 $(firstword ${1}) time -f"%E" sh -c "$(filter-out $(firstword ${1}), ${1})"

default: up

pull:
	$(call message,$(PROJECT_NAME): Downloading / updating Docker images...)
	docker-compose pull
	docker pull $(DOCKER_PHPCS)
	docker pull $(DOCKER_ESLINT)

up:
	$(call message,$(PROJECT_NAME): Starting Docker containers...)
	docker-compose up -d --remove-orphans

stop:
	$(call message,$(PROJECT_NAME): Stopping Docker containers...)
	docker-compose stop

down:
	$(call message,$(PROJECT_NAME): Removing Docker network & containers...)
	docker-compose down -v --remove-orphans

restart:
	$(call message,$(PROJECT_NAME): Restarting Docker containers...)
	@$(MAKE) -s down
	@$(MAKE) -s up

exec:
    # Remove the first argument from the list of make commands.
	$(eval ARGS := $(filter-out $@,$(MAKECMDGOALS)))
	$(eval TARGET := $(firstword $(ARGS)))
	docker-compose exec --user=82:82 $(TARGET) sh

exec\:wodby:
    # Remove the first argument from the list of make commands.
	$(eval ARGS := $(filter-out $@,$(MAKECMDGOALS)))
	$(eval TARGET := $(firstword $(ARGS)))
	docker-compose exec $(TARGET) sh

exec\:root:
    # Remove the first argument from the list of make commands.
	$(eval ARGS := $(filter-out $@,$(MAKECMDGOALS)))
	$(eval TARGET := $(firstword $(ARGS)))
	docker-compose exec --user=0:0 $(TARGET) sh

drush:
    # Remove the first argument from the list of make commands.
	$(eval COMMAND_ARGS := $(filter-out $@,$(MAKECMDGOALS)))
	$(call docker-www-data, php drush --root=/var/www/html/web $(COMMAND_ARGS) --yes)

composer:
    # Remove the first argument from the list of make commands.
	$(eval COMMAND_ARGS := $(filter-out $@,$(MAKECMDGOALS)))
	$(call docker-wodby, php composer $(COMMAND_ARGS))

########################
# Project preparations #
########################

prepare\:backend:
	$(call message,$(PROJECT_NAME): Installing/updating Drupal (Contenta CMS) dependencies...)
	-$(call docker-wodby, php composer install --no-suggest)
	$(call message,$(PROJECT_NAME): Updating permissions for public files...)
	$(call docker-root, php mkdir -p web/sites/default/files)
	$(call docker-root, php chown -R www-data: web/sites/default/files)
	$(call docker-root, php chmod 666 web/sites/default/settings.php)

prepare\:frontend:
	$(call message,$(PROJECT_NAME): Installing dependencies for React.js application...)
	docker-compose run --rm node yarn install

prepare\:platformsh:
	$(call message,$(PROJECT_NAME): Setting Platform.sh git remote..)
	platform project:set-remote $(PLATFORM_PROJECT_ID)

###################################
# Installation from the bottom up #
###################################

install:
	@$(MAKE) -s prepare\:frontend
	@$(MAKE) -s up
	@$(MAKE) -s prepare\:backend
	$(call docker-www-data, php drush -r /var/www/html/web site-install contenta_jsonapi --existing-config \
		--db-url=mysql://$(DB_USER):$(DB_PASSWORD)@$(DB_HOST)/$(DB_NAME) --site-name=$(PROJECT_NAME) --account-pass=admin --yes)
	$(call message,$(PROJECT_NAME): Removing Contenta CMS demo content...)
	@$(MAKE) -s drush pmu recipes_magazin
	$(call message,$(PROJECT_NAME): Preparing test suite...)
	@$(MAKE) -s tests\:prepare
	@$(MAKE) -s tests\:autocomplete
	$(call message,$(PROJECT_NAME): The application is ready!)

######################################################
# Installation from existing Platform.sh environment #
######################################################

install\:platformsh:
	@$(MAKE) -s prepare\:platformsh
	@$(MAKE) -s prepare\:frontend
	@$(MAKE) -s up
	@$(MAKE) -s prepare\:backend
	@$(MAKE) -s files\:sync
	@$(MAKE) -s db\:dump
	@$(MAKE) -s db\:import
	@$(MAKE) -s update
	$(call message,$(PROJECT_NAME): The application is ready!)

#########################################
# Update project after external changes #
#########################################

update:
	@$(MAKE) -s prepare\:frontend
	$(call message,$(PROJECT_NAME): Installing/updating backend dependencies...)
	-$(call docker-wodby, php composer install --no-suggest)
	$(call message,$(PROJECT_NAME): Rebuilding Drupal cache...)
	@$(MAKE) -s drush cache-rebuild
	$(call message,$(PROJECT_NAME): Applying database updates...)
	@$(MAKE) -s drush updatedb
	$(call message,$(PROJECT_NAME): Importing configurations...)
	@$(MAKE) -s drush config-import
	$(call message,$(PROJECT_NAME): Applying entity schema updates...)
	@$(MAKE) -s drush entup

#######################
# Database operations #
#######################

db\:dump:
	$(call message,$(PROJECT_NAME): Creating DB dump from Platform.sh...)
	mkdir -p $(BACKUP_DIR)
	-platform db:dump -y --project=$(PLATFORM_PROJECT_ID) --environment=$(PLATFORM_ENVIRONMENT) --app=$(PLATFORM_APPLICATION_BACKEND) --relationship=$(PLATFORM_RELATIONSHIP_BACKEND) --gzip --file=$(BACKUP_DIR)/$(DB_DUMP_NAME).sql.gz

db\:drop:
	$(call message,$(PROJECT_NAME): Dropping DB from the local environment...)
	@$(MAKE) -s drush sql-drop

db\:import:
	@$(MAKE) -s db\:drop
	$(call message,$(PROJECT_NAME): Importing DB to the local environment...)
	$(call docker-www-data, php zcat ${BACKUP_DIR}/${DB_DUMP_NAME}.sql.gz | drush --root=web sql-cli)

####################
# Files operations #
####################

files\:sync:
	@$(MAKE) -s files\:sync\:public
	@$(MAKE) -s files\:sync\:private

files\:sync\:public:
	$(call message,$(PROJECT_NAME): Creating public files directory...)
	$(call docker-wodby, php mkdir -p web/sites/default/files)

	$(call message,$(PROJECT_NAME): Changing public files ownership to wodby...)
	$(call docker-root, php chown -R wodby: web/sites/default/files)

	$(call message,$(PROJECT_NAME): Downloading public files from Platform.sh...)
	-platform mount:download -y --project=$(PLATFORM_PROJECT_ID) --environment=$(PLATFORM_ENVIRONMENT) --app=$(PLATFORM_APPLICATION_BACKEND) \
        --mount=web/sites/default/files --target=drupal/web/sites/default/files \
        --exclude=css/* --exclude=js/* --exclude=php/* --exclude=styles/*

	$(call message,$(PROJECT_NAME): Changing public files ownership to www-data...)
	$(call docker-root, php chown -R www-data: web/sites/default/files)

files\:sync\:private:
	$(call message,$(PROJECT_NAME): Creating private files directory...)
	$(call docker-wodby, php mkdir -p web/private)

	$(call message,$(PROJECT_NAME): Changing private files ownership to wodby...)
	$(call docker-root, php chown -R wodby: web/private)

	$(call message,$(PROJECT_NAME): Downloading private files from Platform.sh...)
	-platform mount:download -y --project=$(PLATFORM_PROJECT_ID) --environment=$(PLATFORM_ENVIRONMENT) --app=$(PLATFORM_APPLICATION_BACKEND) \
        --mount=private --target=drupal/web/private

	$(call message,$(PROJECT_NAME): Changing private files ownership to www-data...)
	$(call docker-root, php chown -R www-data: web/private)

#######################
# Code quality checks #
#######################

code\:check:
	$(call message,$(PROJECT_NAME): Checking PHP code for compliance with coding standards...)
	docker run --rm \
      -v $(shell pwd)/drupal/web/modules/custom:/app/modules \
      $(DOCKER_PHPCS) phpcs \
      -s --colors --standard=Drupal,DrupalPractice .

	$(call message,$(PROJECT_NAME): Checking Drupal Javascript code for compliance with coding standards...)
	docker run --rm \
      -v $(shell pwd)/drupal/web/modules/custom:/eslint/modules \
      -v $(shell pwd)/drupal/.eslintrc.json:/eslint/.eslintrc.json \
      $(DOCKER_ESLINT) .

	$(call message,$(PROJECT_NAME): Checking React.js code for compliance with coding standards...)
	docker-compose run -T --rm node yarn --silent run eslint

code\:fix:
	$(call message,$(PROJECT_NAME): Auto-fixing Drupal PHP code issues...)
	docker run --rm \
      -v $(shell pwd)/drupal/web/modules/custom:/app/modules \
      $(DOCKER_PHPCS) phpcbf \
      -s --colors --standard=Drupal,DrupalPractice .

	$(call message,$(PROJECT_NAME): Auto-fixing Drupal JS code issues...)
	docker run --rm \
      -v $(shell pwd)/drupal/web/modules/custom:/eslint/modules \
      -v $(shell pwd)/drupal/.eslintrc.json:/eslint/.eslintrc.json \
      $(DOCKER_ESLINT) --fix .

	$(call message,$(PROJECT_NAME): Auto-fixing React.js code issues...)
	docker-compose run -T --rm node yarn --silent run eslint --fix

#######################
# Frontend operations #
#######################

yarn:
	$(call message,$(PROJECT_NAME): Running Yarn command...)
	$(eval ARGS := $(filter-out $@,$(MAKECMDGOALS)))
	docker-compose run --rm node yarn $(ARGS)

logs:
	$(call message,$(PROJECT_NAME): Streaming the Next.js application logs...)
	docker-compose logs -f node

##############################
# Testing framework commands #
##############################

tests\:prepare:
	$(call message,$(PROJECT_NAME): Preparing Codeception framework for testing...)
	docker-compose run --rm codecept build

tests\:run:
	$(call message,$(PROJECT_NAME): Running Codeception tests...)
	$(eval ARGS := $(filter-out $@,$(MAKECMDGOALS)))
	docker-compose run --rm codecept run $(ARGS) --debug

tests\:cli:
	$(call message,$(PROJECT_NAME): Opening Codeception container CLI...)
	docker-compose run --rm --entrypoint bash codecept

tests\:autocomplete:
	$(call message,$(PROJECT_NAME): Copying Codeception codbasee in .codecept folder to enable IDE autocomplete...)
	docker-compose up -d codecept
	rm -rf .codecept
	docker cp $(PROJECT_NAME)_codecept:/repo/ .codecept
	rm -rf .codecept/.git

# https://stackoverflow.com/a/6273809/1826109
%:
	@:
