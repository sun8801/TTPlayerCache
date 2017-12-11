
Pod::Spec.new do |s|

  s.name         = "TTPlayerCache"
  s.version      = "0.1.2"
  s.summary      = "A cache for AVPlayer of TTPlayerCache."  
  s.homepage     = "https://github.com/sun8801/TTPlayerCache"
  s.license      = "MIT"
  s.author       = { "sun" => "sun8801@users.noreply.github.com" }

  s.platform     = :ios, "8.0"
  s.ios.deployment_target = "8.0"


  # ――― Source Location ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  Specify the location from where the source should be retrieved.
  #  Supports git, hg, bzr, svn and HTTP.
  #

  s.source       = { :git => 'https://github.com/sun8801/TTPlayerCache.git', 
                     :tag => s.version.to_s ,
                     :submodules => true}
  s.requires_arc = true
  s.frameworks   = "UIKit","AVFoundation","SystemConfiguration","MobileCoreServices"

  s.source_files        = 'Source/TTPlayerCache/TTPlayerCache{,Macro}.h'
  s.public_header_files = 'source/TTPlayerCache/TTPlayerCache{,Macro}.h'


  s.subspec 'Reachability' do |ss|
    ss.source_files        = 'Source/TTPlayerCache/Reachability/*.{h,m}'
    ss.public_header_files = 'Source/TTPlayerCache/Reachability/*.h'
  end

  s.subspec 'Category' do |ss| 
    ss.source_files        = 'Source/TTPlayerCache/Category/*.{h,m}'
    ss.public_header_files = 'Source/TTPlayerCache/Category/*.h'
  end

  s.subspec 'PlayerCache' do |ss|
    ss.dependency 'TTPlayerCache/Category'
    ss.dependency 'TTPlayerCache/Reachability'

    ss.source_files        = 'Source/TTPlayerCache/TTResourceLoader{Delegate,Data,Cache}.{h,m}'
    ss.public_header_files = 'Source/TTPlayerCache/TTResourceLoader{Delegate,Data,Cache}.h'
  end

end
