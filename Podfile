platform :ios, '15.0'
use_frameworks!

workspace 'DuplicateContentDetection'

# Set deployment target for all pods
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
    end
  end
end

def aws_pods
  pod 'AWSCore', '~> 2.33.0'
  pod 'AWSS3', '~> 2.33.0'
  pod 'AWSDynamoDB', '~> 2.33.0'
  pod 'AWSAPIGateway', '~> 2.33.0'
  pod 'AWSCognitoIdentityProvider', '~> 2.33.0'
end

target 'DuplicateContentDetection' do
  project 'DuplicateContentDetection'
  aws_pods

  target 'DuplicateContentDetectionTests' do
    inherit! :complete
  end
end

target 'SignalServiceKit' do
  project 'DuplicateContentDetection'
  aws_pods
end 