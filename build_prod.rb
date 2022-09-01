#!/usr/bin/env ruby

require 'yaml'

ci_token = YAML.load_file("#{Dir.home}/.circleci/cli.yml")['token']

`curl --request POST --url https://circleci.com/api/v2/project/github/GoCarrot/antora-ui-teak/pipeline --header 'Circle-Token: #{ci_token}' --header 'content-type: application/json' --data '{"parameters":{"build_type":"production"}}'`
