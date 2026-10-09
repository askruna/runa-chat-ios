Pod::Spec.new do |s|
  s.name             = 'RunaChat'
  s.version          = '1.0.3'
  s.summary          = 'The Runa AI shopping assistant as a screen in your iOS app.'
  s.description      = 'The Runa AI shopping assistant as a screen in your app. One call to open, two delegate methods to connect your cart; the chat itself is hosted and updated by Runa.'
  s.homepage         = 'https://github.com/askruna/runa-chat-ios'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Runa' => 'adrian@askruna.ai' }
  s.source           = { :git => 'https://github.com/askruna/runa-chat-ios.git', :tag => s.version.to_s }
  s.platform         = :ios, '13.0'
  s.swift_versions   = ['5.7']
  s.source_files     = 'Sources/RunaChat/**/*.swift'
  s.frameworks       = 'UIKit', 'WebKit', 'SafariServices'
end
