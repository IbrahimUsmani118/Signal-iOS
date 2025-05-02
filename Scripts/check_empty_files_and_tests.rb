#!/usr/bin/env ruby

require 'fileutils'
require 'json'
require 'time'
require 'xcodeproj'

class ProjectChecker
  def initialize
    @project_root = File.expand_path(File.join(File.dirname(__FILE__), '..'))
    @report = {
      timestamp: Time.now.iso8601,
      empty_files: [],
      test_results: {},
      errors: [],
      warnings: [],
      project_stats: {
        total_files: 0,
        swift_files: 0,
        test_files: 0,
        empty_files: 0
      }
    }
  end

  def run
    analyze_project
    check_empty_files
    run_swift_tests
    generate_report
  end

  private

  def analyze_project
    puts "Analyzing project structure..."
    
    # Count all files
    @report[:project_stats][:total_files] = Dir.glob(File.join(@project_root, '**', '*')).count
    
    # Count Swift files
    swift_files = Dir.glob(File.join(@project_root, '**', '*.swift'))
    @report[:project_stats][:swift_files] = swift_files.size
    
    # Count test files
    test_files = swift_files.select { |f| f.include?('Tests/') || f.include?('Test/') }
    @report[:project_stats][:test_files] = test_files.size
    
    # Analyze Xcode project structure
    begin
      project_path = Dir.glob(File.join(@project_root, '*.xcodeproj')).first
      if project_path
        project = Xcodeproj::Project.open(project_path)
        analyze_targets(project)
      end
    rescue => e
      @report[:warnings] << {
        type: 'project_analysis',
        message: "Failed to analyze Xcode project: #{e.message}",
        timestamp: Time.now.iso8601
      }
    end
  end

  def analyze_targets(project)
    project.targets.each do |target|
      next unless target.is_a?(Xcodeproj::Project::Object::PBXNativeTarget)
      
      test_files = target.source_build_phase.files.select do |file|
        file.file_ref&.path&.end_with?('.swift')
      end
      
      @report[:project_stats][:targets] ||= {}
      @report[:project_stats][:targets][target.name] = {
        type: target.product_type,
        source_files: test_files.size,
        dependencies: target.dependencies.size
      }
    end
  end

  def check_empty_files
    puts "Checking for empty files..."
    
    # Find all Swift files
    swift_files = Dir.glob(File.join(@project_root, '**', '*.swift'))
    
    swift_files.each do |file|
      if File.size(file) == 0
        @report[:empty_files] << {
          path: file.gsub(@project_root, ''),
          last_modified: File.mtime(file).iso8601,
          target: determine_target(file)
        }
      end
    end
    
    @report[:project_stats][:empty_files] = @report[:empty_files].size
  end

  def determine_target(file_path)
    if file_path.include?('SignalServiceKit')
      'SignalServiceKit'
    elsif file_path.include?('DuplicateContentDetection')
      'DuplicateContentDetection'
    else
      'Unknown'
    end
  end

  def run_swift_tests
    puts "Running Swift tests..."
    
    # Run tests for each test target
    test_targets = [
      'SignalServiceKitTests',
      'DuplicateContentDetectionTests'
    ]
    
    test_targets.each do |target|
      begin
        # First try to build
        build_result = `cd #{@project_root} && xcodebuild build -scheme #{target} -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1`
        
        if $?.success?
          # If build succeeds, run tests
          test_result = `cd #{@project_root} && xcodebuild test -scheme #{target} -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1`
          
          @report[:test_results][target] = {
            success: $?.success?,
            build_output: build_result,
            test_output: test_result,
            timestamp: Time.now.iso8601,
            test_count: extract_test_count(test_result),
            failures: extract_failures(test_result)
          }
        else
          @report[:test_results][target] = {
            success: false,
            build_output: build_result,
            test_output: nil,
            timestamp: Time.now.iso8601,
            error: 'Build failed'
          }
        end
      rescue => e
        @report[:errors] << {
          target: target,
          error: e.message,
          timestamp: Time.now.iso8601
        }
      end
    end
  end

  def extract_test_count(output)
    if match = output.match(/Test Suite '.*' finished at .*\.\nExecuted (\d+) tests/)
      match[1].to_i
    else
      0
    end
  end

  def extract_failures(output)
    failures = []
    output.scan(/Test Case '.*' failed \(.*\)/) do |match|
      failures << match
    end
    failures
  end

  def generate_report
    report_path = File.join(@project_root, 'test-reports', 'project_check_report.json')
    FileUtils.mkdir_p(File.dirname(report_path))
    
    File.write(report_path, JSON.pretty_generate(@report))
    
    # Print summary
    puts "\n=== Project Check Report ==="
    puts "Timestamp: #{@report[:timestamp]}"
    
    puts "\nProject Statistics:"
    puts "  Total Files: #{@report[:project_stats][:total_files]}"
    puts "  Swift Files: #{@report[:project_stats][:swift_files]}"
    puts "  Test Files: #{@report[:project_stats][:test_files]}"
    puts "  Empty Files: #{@report[:project_stats][:empty_files]}"
    
    puts "\nEmpty Files:"
    @report[:empty_files].each do |file|
      puts "  - #{file[:path]} (Target: #{file[:target]})"
    end
    
    puts "\nTest Results:"
    @report[:test_results].each do |target, result|
      status = result[:success] ? "✅ PASSED" : "❌ FAILED"
      puts "  #{target}: #{status}"
      if result[:test_count]
        puts "    Tests Run: #{result[:test_count]}"
      end
      if result[:failures]&.any?
        puts "    Failures:"
        result[:failures].each { |f| puts "      - #{f}" }
      end
    end
    
    if @report[:errors].any?
      puts "\nErrors:"
      @report[:errors].each do |error|
        puts "  - #{error[:target]}: #{error[:error]}"
      end
    end
    
    if @report[:warnings].any?
      puts "\nWarnings:"
      @report[:warnings].each do |warning|
        puts "  - #{warning[:type]}: #{warning[:message]}"
      end
    end
    
    puts "\nReport saved to: #{report_path}"
  end
end

# Run the checker
ProjectChecker.new.run 