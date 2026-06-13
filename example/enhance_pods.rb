#!/usr/bin/env ruby
# frozen_string_literal: true

# ═══════════════════════════════════════════════════════════════
#  Pod 模板增强脚本
#  给每个 pod 模板增加 15+ 源文件（ObjC + Swift 混合）
#  增加资源文件（xib, storyboard, asset catalog）
#  模拟真实项目的混编 + 资源负载
# ═══════════════════════════════════════════════════════════════

require 'fileutils'
require 'json'

BASE_DIR = File.expand_path(File.dirname(__FILE__))
TEMPLATES_DIR = File.join(BASE_DIR, 'pod_templates')
GENERATED_PODS_DIR = File.join(BASE_DIR, 'generated_pods')

puts "╔══════════════════════════════════════════════════════════════╗"
puts "║  Pod 模板增强                                               ║"
puts "╚══════════════════════════════════════════════════════════════╝"
puts ""

# ── 增强 Pod 模板 ─────────────────────────────────────────────
(1..20).each do |tnum|
  tmpl_name = format('PodBase%02d', tnum)
  tmpl_dir = File.join(TEMPLATES_DIR, tmpl_name)
  classes_dir = File.join(tmpl_dir, 'Classes')
  assets_dir = File.join(tmpl_dir, 'Assets')
  resources_dir = File.join(tmpl_dir, 'Resources')

  next unless File.directory?(tmpl_dir)

  FileUtils.mkdir_p(classes_dir)
  FileUtils.mkdir_p(assets_dir)
  FileUtils.mkdir_p(resources_dir)

  # ── 添加更多 ObjC 源文件（模拟网络层、工具类、Model） ──
  objc_files = [
    ["#{tmpl_name}NetworkClient.h", "#{tmpl_name}NetworkClient.m"],
    ["#{tmpl_name}DataManager.h", "#{tmpl_name}DataManager.m"],
    ["#{tmpl_name}CacheManager.h", "#{tmpl_name}CacheManager.m"],
    ["#{tmpl_name}ConfigService.h", "#{tmpl_name}ConfigService.m"],
    ["#{tmpl_name}AnalyticsTracker.h", "#{tmpl_name}AnalyticsTracker.m"],
    ["#{tmpl_name}Logger.h", "#{tmpl_name}Logger.m"],
    ["#{tmpl_name}Constant.h", "#{tmpl_name}Constant.m"],
  ]

  objc_files.each do |h_file, m_file|
    # Header
    File.write(File.join(classes_dir, h_file), <<~OBJC)
      #import <Foundation/Foundation.h>
      #import <UIKit/UIKit.h>

      NS_ASSUME_NONNULL_BEGIN

      @interface #{tmpl_name}#{h_file.sub('.h', '').sub(tmpl_name, '')} : NSObject

      @property (nonatomic, strong, readonly) NSString *name;
      @property (nonatomic, assign, readonly) NSInteger versionCode;

      - (instancetype)initWithName:(NSString *)name;
      - (void)configureWithOptions:(nullable NSDictionary *)options;
      - (void)reset;
      + (instancetype)shared;

      @end

      NS_ASSUME_NONNULL_END
    OBJC

    # Implementation
    File.write(File.join(classes_dir, m_file), <<~OBJC)
      #import "#{h_file}"

      @interface #{tmpl_name}#{h_file.sub('.h', '').sub(tmpl_name, '')} ()

      @property (nonatomic, strong, readwrite) NSString *name;
      @property (nonatomic, assign, readwrite) NSInteger versionCode;

      @end

      static id _sharedInstance = nil;

      @implementation #{tmpl_name}#{h_file.sub('.h', '').sub(tmpl_name, '')}

      - (instancetype)initWithName:(NSString *)name {
          self = [super init];
          if (self) {
              _name = [name copy];
              _versionCode = 1;
          }
          return self;
      }

      - (void)configureWithOptions:(nullable NSDictionary *)options {
          if (options) {
              id version = options[@"version"];
              if ([version respondsToSelector:@selector(integerValue)]) {
                  _versionCode = [version integerValue];
              }
          }
      }

      - (void)reset {
          _versionCode = 1;
      }

      + (instancetype)shared {
          static dispatch_once_t onceToken;
          dispatch_once(&onceToken, ^{
              _sharedInstance = [[self alloc] init];
          });
          return _sharedInstance;
      }

      @end
    OBJC
  end

  # ── 添加更多 Swift 源文件（模拟视图层、扩展、协议） ──
  swift_files = [
    "#{tmpl_name}ViewController.swift",
    "#{tmpl_name}TableViewCell.swift",
    "#{tmpl_name}CollectionViewLayout.swift",
    "#{tmpl_name}ViewModel.swift",
    "#{tmpl_name}Coordinator.swift",
    "#{tmpl_name}Router.swift",
    "#{tmpl_name}Protocol.swift",
    "#{tmpl_name}Extensions.swift",
    "#{tmpl_name}Factory.swift",
  ]

  swift_files.each do |sf|
    base = sf.sub('.swift', '').sub(tmpl_name, '')
    File.write(File.join(classes_dir, sf), <<~SWIFT)
      import Foundation
      import UIKit

      // MARK: - #{tmpl_name}#{base}

      /// Generated controller/presenter for #{tmpl_name}#{base}
      /// This file is part of the auto-generated performance testing pods.

      @objc public class #{tmpl_name}#{base}: NSObject {

          // MARK: - Properties

          public let identifier: String
          public let createdAt: Date

          // MARK: - Initialization

          public override init() {
              self.identifier = UUID().uuidString
              self.createdAt = Date()
              super.init()
          }

          public init(identifier: String) {
              self.identifier = identifier
              self.createdAt = Date()
          }

          // MARK: - Public Methods

          public func configure(with data: [String: Any]) {
              // Configuration logic placeholder
              debugPrint("[#{tmpl_name}#{base}] Configured with \\(data.count) parameters")
          }

          public func reset() {
              debugPrint("[#{tmpl_name}#{base}] Reset called")
          }

          // MARK: - Debug

          public override var description: String {
              return "\\(type(of: self))(\\(identifier))"
          }
      }
    SWIFT
  end

  # ── 添加资源文件 ──
  # XIB 文件
  xib_name = "#{tmpl_name}View.xib"
  File.write(File.join(resources_dir, xib_name), <<~XIB)
    <?xml version="1.0" encoding="UTF-8"?>
    <document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB" version="3.0">
      <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="22222"/>
      </dependencies>
      <objects>
        <viewController id="1" customClass="#{tmpl_name}ViewController">
          <view key="view" contentMode="scaleToFill" id="2">
            <rect key="frame" x="0.0" y="0.0" width="375" height="812"/>
            <subviews>
              <label opaque="NO" userInteractionEnabled="NO" contentMode="left" text="#{tmpl_name}" textAlignment="natural" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" adjustsFontSizeToFit="NO" id="3">
                <rect key="frame" x="16" y="100" width="343" height="21"/>
                <fontDescription key="fontDescription" type="system" pointSize="17"/>
                <color key="textColor" red="0.0" green="0.0" blue="0.0" alpha="1" colorSpace="custom"/>
              </label>
            </subviews>
            <color key="backgroundColor" red="1" green="1" blue="1" alpha="1" colorSpace="custom"/>
          </view>
        </viewController>
      </objects>
    </document>
  XIB

  # Storyboard 文件
  sb_file = "#{tmpl_name}Storyboard.storyboard"
  File.write(File.join(resources_dir, sb_file), <<~SB)
    <?xml version="1.0" encoding="UTF-8"?>
    <document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0">
      <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="22222"/>
      </dependencies>
      <scenes>
        <scene sceneID="1">
          <objects>
            <viewController storyboardIdentifier="#{tmpl_name}MainVC" id="1" customClass="#{tmpl_name}ViewController">
              <view key="view" contentMode="scaleToFill" id="2">
                <rect key="frame" x="0.0" y="0.0" width="375" height="812"/>
                <subviews>
                  <label opaque="NO" text="#{tmpl_name} Main" textAlignment="natural" id="3">
                    <rect key="frame" x="16" y="100" width="343" height="21"/>
                    <fontDescription key="fontDescription" type="system" pointSize="17"/>
                  </label>
                  <button opaque="NO" contentMode="scaleToFill" contentHorizontalAlignment="center" contentVerticalAlignment="center" id="4">
                    <rect key="frame" x="16" y="140" width="343" height="44"/>
                    <state key="normal" title="Tap Here"/>
                    <connections><action selector="buttonTapped:" destination="1" eventType="touchUpInside" id="5"/></connections>
                  </button>
                </subviews>
              </view>
            </viewController>
          </objects>
        </scene>
      </scenes>
    </document>
  SB

  # JSON 配置文件
  json = {
    name: tmpl_name,
    version: "1.0.0",
    configs: {
      api_url: "https://api.example.com/#{tmpl_name.downcase}",
      timeout: 30,
      retry_count: 3,
      features: (1..10).map { |i| "feature_#{i}" }
    },
    resources: {
      images: (1..5).map { |i| "#{tmpl_name.downcase}_icon_#{i}" },
      strings: (1..5).map { |i| "#{tmpl_name.downcase}_string_#{i}" }
    }
  }.to_json
  File.write(File.join(resources_dir, "#{tmpl_name}Config.json"), json)

  puts "  ✅ Enhanced #{tmpl_name}: #{objc_files.size*2} ObjC + #{swift_files.size} Swift + 3 resource files"
end

puts ""
puts "━━━ 模板增强完成！重新运行 generate_podfile.rb 生成 150 个增强 pod..."
puts ""
