
Pod::Spec.new do |s|

  s.name         = "TTPlayerCache"
  s.version      = "0.0.1"
  s.summary      = "A cache for AVPlayer of TTPlayerCache."  
  s.homepage     = "https://github.com/sun8801/TTPlayerCache"
  s.license      = "MIT"
  s.author       = { "sun" => "sun8801@users.noreply.github.com" }

  s.platform     = :ios, "7.0"
  s.ios.deployment_target = "7.0"


  # ――― Source Location ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  Specify the location from where the source should be retrieved.
  #  Supports git, hg, bzr, svn and HTTP.
  #

  s.source       = { :git => 'https://github.com/sun8801/TTPlayerCache.git', 
                     :tag => s.version.to_s }
  s.source_files = "Source/**/*.{h,m}"

  s.frameworks   = "UIKit","AVFoundation","SystemConfiguration","MobileCoreServices"
  s.requires_arc = true

end
