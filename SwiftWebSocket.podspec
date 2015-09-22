Pod::Spec.new do |s|
  s.name                  = "SwiftWebSocket"
  s.version               = "2.1.0"
  s.summary               = "A high performance WebSocket client library for Swift."
  s.homepage              = "https://github.com/tidwall/SwiftWebSocket"
  s.license               = { :type => "Attribution License", :file => "LICENSE" }
  s.source                = { :git => "https://github.com/tidwall/SwiftWebSocket.git", :tag => "v#{s.version}" }
  s.authors               = { 'Josh Baker' => 'joshbaker77@gmail.com' }
  s.social_media_url      = "https://twitter.com/tidwall"
  s.ios.platform          = :ios, '8.0'
  s.ios.deployment_target = "8.0"
  s.osx.platform          = :osx, '10.10'
  s.osx.deployment_target = "10.10"
  s.source_files          = "Source/*.swift"
  s.requires_arc          = true
  s.libraries             = 'z'
end
