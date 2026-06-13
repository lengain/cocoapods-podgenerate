#!/usr/bin/env ruby
# frozen_string_literal: true

$stdout.sync = true

require 'cocoapods'

plugin_lib = File.expand_path('../../lib', __dir__)
$LOAD_PATH.unshift(plugin_lib)
require 'cocoapods-podgenerate'
Pod::PodGenerate.activate

ENV['COCOAPODS_PODGENERATE_DEBUG'] = '1' if ARGV.include?('--debug')

config = Pod::Config.instance
config.verbose = ARGV.include?('--verbose')

Pod::UI.puts '[cocoapods-podgenerate] PodGenerate plugin active'

installer = Pod::Installer.new(config.sandbox, config.podfile, config.lockfile)
installer.install!
