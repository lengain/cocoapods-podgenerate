#!/usr/bin/env ruby
# frozen_string_literal: true

# Wrapper script: loads CocoaPods, applies PodGenerate patches, runs pod install.

$stdout.sync = true

# Load CocoaPods
require 'cocoapods'

# Load & activate PodGenerate plugin
plugin_lib = File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift(plugin_lib)
require 'cocoapods-podgenerate'
Pod::PodGenerate.activate

# Debug mode
ENV['COCOAPODS_PODGENERATE_DEBUG'] = '1' if ARGV.include?('--debug')

# Run install
config = Pod::Config.instance
config.verbose = ARGV.include?('--verbose')

Pod::UI.puts '[cocoapods-podgenerate] PodGenerate plugin active'

# Direct installer invocation (same as pod install command)
installer = Pod::Installer.new(config.sandbox, config.podfile, config.lockfile)
installer.install!
