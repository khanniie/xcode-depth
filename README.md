# AR Depth

This iOS app displays the segmented depth image created by Apple's Arkit3.

![img1](readme_assets/depth.gif)

The app passes the AR camera information, including the depth texture and the segmentation buffer to the shader, which then compiles the textures as shown below in [Shaders.metal](https://github.com/khanniie/xcode-depth/blob/master/ARMatteExampleSwift/Shaders.metal#L201):

```C
//clamp to between 0 or 1 (documentation says depth value represents distance in meters)
dilatedLinearDepth = (dilatedLinearDepth > 1) ? 1: ((dilatedLinearDepth < 0) ? 0 : dilatedLinearDepth);

//combine segmentation buffer with depth value to get a cleaner result
//floor at 0.1 so that you can at least see the outline of the arm if the depth value is too small
//we also "invert" the value of the depth so that closer is brighter
return alpha * (0.1 + 0.9 * (1 - dilatedLinearDepth));
```

## Credits
based on Apple's ["Effecting People Occlusion in Custom Renderers"](https://developer.apple.com/documentation/arkit/effecting_people_occlusion_in_custom_renderers) code
