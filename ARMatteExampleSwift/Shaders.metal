/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The sample app's shaders.
*/

#include <metal_stdlib>
#include <simd/simd.h>

// Include header shared between this Metal shader code and C code executing Metal API commands. 
#import "ShaderTypes.h"

using namespace metal;

typedef struct {
    float2 position [[attribute(kVertexAttributePosition)]];
    float2 texCoord [[attribute(kVertexAttributeTexcoord)]];
} ImageVertex;


typedef struct {
    float4 position [[position]];
    float2 texCoord;
} ImageColorInOut;


// This defines the captured image vertex function.
vertex ImageColorInOut capturedImageVertexTransform(ImageVertex in [[stage_in]]) {
    ImageColorInOut out;
    
    // Pass through the image vertex's position.
    out.position = float4(in.position, 0.0, 1.0);
    
    // Pass through the texture coordinate.
    out.texCoord = in.texCoord;
    
    return out;
}

// Convert from YCbCr to rgb
float4 ycbcrToRGBTransform(float4 y, float4 CbCr) {
    const float4x4 ycbcrToRGBTransform = float4x4(
      float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
      float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
      float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
      float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f)
    );

    float4 ycbcr = float4(y.r, CbCr.rg, 1.0);
    return ycbcrToRGBTransform * ycbcr;
}

// This defines the captured image fragment function.
fragment float4 capturedImageFragmentShader(ImageColorInOut in [[stage_in]],
                                            texture2d<float, access::sample> capturedImageTextureY [[ texture(kTextureIndexY) ]],
                                            texture2d<float, access::sample> capturedImageTextureCbCr [[ texture(kTextureIndexCbCr) ]]) {
    
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);
    
    // Sample Y and CbCr textures to get the YCbCr color at the given texture coordinate.
    return ycbcrToRGBTransform(capturedImageTextureY.sample(colorSampler, in.texCoord),
                               capturedImageTextureCbCr.sample(colorSampler, in.texCoord));
}


typedef struct {
    float3 position [[attribute(kVertexAttributePosition)]];
    float2 texCoord [[attribute(kVertexAttributeTexcoord)]];
    half3 normal    [[attribute(kVertexAttributeNormal)]];
} Vertex;


typedef struct {
    float4 position [[position]];
    float4 color;
    half3  eyePosition;
    half3  normal;
} ColorInOut;


// Anchor the geometry vertex function.
vertex ColorInOut anchorGeometryVertexTransform(Vertex in [[stage_in]],
                                                constant SharedUniforms &sharedUniforms [[ buffer(kBufferIndexSharedUniforms) ]],
                                                constant InstanceUniforms *instanceUniforms [[ buffer(kBufferIndexInstanceUniforms) ]],
                                                ushort vid [[vertex_id]],
                                                ushort iid [[instance_id]]) {
    ColorInOut out;
    
    // Make position a float4 to perform 4x4 matrix math on it.
    float4 position = float4(in.position, 1.0);
    
    float4x4 modelMatrix = instanceUniforms[iid].modelMatrix;
    float4x4 modelViewMatrix = sharedUniforms.viewMatrix * modelMatrix;
    
    // Calculate the position of the vertex in clip space and output for clipping and rasterization.
    out.position = sharedUniforms.projectionMatrix * modelViewMatrix * position;
    
    // Set each face to a different color.
    ushort colorID = vid / 4 % 6;
    out.color = colorID == 0 ? float4(0.0, 1.0, 0.0, 1.0) // Right face
              : colorID == 1 ? float4(1.0, 0.0, 0.0, 1.0) // Left face
              : colorID == 2 ? float4(0.0, 0.0, 1.0, 1.0) // Top face
              : colorID == 3 ? float4(1.0, 0.5, 0.0, 1.0) // Bottom face
              : colorID == 4 ? float4(1.0, 1.0, 0.0, 1.0) // Back face
              : float4(1.0, 1.0, 1.0, 1.0); // Front face
    
    // Calculate the positon of the vertex in eye space.
    out.eyePosition = half3((modelViewMatrix * position).xyz);
    
    // Rotate the normals to world coordinates.
    float4 normal = modelMatrix * float4(in.normal.x, in.normal.y, in.normal.z, 0.0f);
    out.normal = normalize(half3(normal.xyz));
    
    return out;
}

// Anchor the geometry fragment function.
fragment float4 anchorGeometryFragmentLighting(ColorInOut in [[stage_in]],
                                               constant SharedUniforms &uniforms [[ buffer(kBufferIndexSharedUniforms) ]]) {
    
    float3 normal = float3(in.normal);
    
    // Calculate the contribution of the directional light as a sum of diffuse and specular terms.
    float3 directionalContribution = float3(0);
    {
        // Light falls off based on how closely aligned the surface normal is to the light direction.
        float nDotL = saturate(dot(normal, -uniforms.directionalLightDirection));
        
        // The diffuse term is then the product of the light color, the surface material
        // reflectance, and the falloff.
        float3 diffuseTerm = uniforms.directionalLightColor * nDotL;
        
        // Apply specular lighting...
        
        // 1) Calculate the halfway vector between the light direction and the direction they eye is looking.
        float3 halfwayVector = normalize(-uniforms.directionalLightDirection - float3(in.eyePosition));
        
        // 2) Calculate the reflection angle between our reflection vector and the eye's direction.
        float reflectionAngle = saturate(dot(normal, halfwayVector));
        
        // 3) Calculate the specular intensity by multiplying our reflection angle with our object's
        //    shininess.
        float specularIntensity = saturate(powr(reflectionAngle, uniforms.materialShininess));
        
        // 4) Obtain the specular term by multiplying the intensity by our light's color.
        float3 specularTerm = uniforms.directionalLightColor * specularIntensity;
        
        // Calculate total contribution from this light is the sum of the diffuse and specular values.
        directionalContribution = diffuseTerm + specularTerm;
    }
    
    // The ambient contribution, which is an approximation for global, indirect lighting, is
    // the product of the ambient light intensity multiplied by the material's reflectance.
    float3 ambientContribution = uniforms.ambientLightColor;
    
    // Now that we have the contributions our light sources in the scene, we sum them together
    // to get the fragment's lighting value.
    float3 lightContributions = ambientContribution + directionalContribution;
    
    // Compute the final color by multiplying the sample from our color maps by the fragment's
    // lighting value.
    float3 color = in.color.rgb * lightContributions;
    
    // Use the color we just computed and the alpha channel of our
    // colorMap for this fragment's alpha value.
    return float4(color, in.color.w);
}


typedef struct {
    float2 position;
    float2 texCoord;
} CompositeVertex;

typedef struct {
    float4 position [[position]];
    float2 texCoordCamera;
    float2 texCoordScene;
} CompositeColorInOut;

// Composite the image vertex function.
vertex CompositeColorInOut compositeImageVertexTransform(const device CompositeVertex* cameraVertices [[ buffer(0) ]],
                                                         const device CompositeVertex* sceneVertices [[ buffer(1) ]],
                                                         unsigned int vid [[ vertex_id ]]) {
    CompositeColorInOut out;

    const device CompositeVertex& cv = cameraVertices[vid];
    const device CompositeVertex& sv = sceneVertices[vid];

    out.position = float4(cv.position, 0.0, 1.0);
    out.texCoordCamera = cv.texCoord;
    out.texCoordScene = sv.texCoord;

    return out;
}

// Composite the image fragment function.
fragment half4 compositeImageFragmentShader(CompositeColorInOut in [[ stage_in ]],
                                    texture2d<float, access::sample> alphaTexture [[ texture(4) ]],
                                    texture2d<float, access::sample> dilatedDepthTexture [[ texture(5) ]],
                                    constant SharedUniforms &uniforms [[ buffer(kBufferIndexSharedUniforms) ]])
{
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    
    //get coordinate
    float2 cameraTexCoord = in.texCoordCamera;
    
    //get value of segmentation buffer
    half alpha = half(alphaTexture.sample(s, cameraTexCoord).r);

    if (uniforms.useDepth) {
        //get value of depth buffer
        float dilatedLinearDepth = half(dilatedDepthTexture.sample(s, cameraTexCoord).r);
        
        //clamp to between 0 or 1 (documentation says depth value represents distance in meters)
        dilatedLinearDepth = (dilatedLinearDepth > 1) ? 1: ((dilatedLinearDepth < 0) ? 0 : dilatedLinearDepth);
        
        //combine segmentation buffer with depth value to get a cleaner result
        //floor at 0.1 so that you can at least see the outline of the arm if the depth value is too small
        //we also "invert" the value of the depth so that closer is brighter
        return alpha * (0.1 + 0.9 * (1 - dilatedLinearDepth));
    }
    
    //just in case useDepth is false, we return something anyways
    return half(dilatedDepthTexture.sample(s, cameraTexCoord).r);
}

