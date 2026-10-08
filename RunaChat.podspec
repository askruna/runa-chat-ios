Pod::Spec.new do |s|
  s.name             = 'RunaChat'
  s.version          = '1.0.2'
  s.summary          = 'The Runa AI shopping assistant as a screen in your iOS app.'
  s.description      = 'A full-screen WebView on the Runa chat page with a small bridge to your cart and product screens. One call to open, two delegate methods to connect your cart.'
  s.homepage         = 'https://github.com/askruna/runa-chat-ios'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Runa' => 'adrian@askruna.ai' }
  s.source           = { :git => 'https://github.com/askruna/runa-chat-ios.git', :tag => s.version.to_s }
  s.platform         = :ios, '13.0'
  s.swift_versions   = ['5.7']
  s.source_files     = 'Sources/RunaChat/**/*.swift'
  s.frameworks       = 'UIKit', 'WebKit'
end
