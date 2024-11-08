/////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Tencent is pleased to support the open source community by making tgfx available.
//
//  Copyright (C) 2023 THL A29 Limited, a Tencent company. All rights reserved.
//
//  Licensed under the BSD 3-Clause License (the "License"); you may not use this file except
//  in compliance with the License. You may obtain a copy of the License at
//
//      https://opensource.org/licenses/BSD-3-Clause
//
//  unless required by applicable law or agreed to in writing, software distributed under the
//  license is distributed on an "as is" basis, without warranties or conditions of any kind,
//  either express or implied. see the license for the specific language governing permissions
//  and limitations under the license.
//
/////////////////////////////////////////////////////////////////////////////////////////////////

#include "EAGLHardwareTexture.h"
#include "core/utils/UniqueID.h"
#include "gpu/opengl/GLCaps.h"
#include "gpu/opengl/GLSampler.h"
#include "tgfx/gpu/opengl/eagl/EAGLDevice.h"

namespace tgfx {
static CVOpenGLESTextureRef GetTextureRef(Context* context, CVPixelBufferRef pixelBuffer,
                                          PixelFormat pixelFormat,
                                          CVOpenGLESTextureCacheRef textureCache) {
  if (textureCache == nil) {
    return nil;
  }
  auto width = static_cast<int>(CVPixelBufferGetWidth(pixelBuffer));
  auto height = static_cast<int>(CVPixelBufferGetHeight(pixelBuffer));
  CVOpenGLESTextureRef texture = nil;
  auto caps = GLCaps::Get(context);
  const auto& format = caps->getTextureFormat(pixelFormat);
  // The returned texture object has a strong reference count of 1.
  CVReturn result = CVOpenGLESTextureCacheCreateTextureFromImage(
      kCFAllocatorDefault, textureCache, pixelBuffer, NULL,             /* texture attributes */
      GL_TEXTURE_2D, static_cast<GLint>(format.internalFormatTexImage), /* opengl format */
      width, height, format.externalFormat,                             /* native iOS format */
      GL_UNSIGNED_BYTE, 0, &texture);
  if (result != kCVReturnSuccess && texture != nil) {
    CFRelease(texture);
    texture = nil;
  }
  return texture;
}

std::shared_ptr<EAGLHardwareTexture> EAGLHardwareTexture::MakeFrom(Context* context,
                                                                   CVPixelBufferRef pixelBuffer) {
  std::shared_ptr<EAGLHardwareTexture> glTexture = nullptr;
  auto scratchKey = ComputeScratchKey(pixelBuffer);
  glTexture = Resource::Find<EAGLHardwareTexture>(context, scratchKey);
  if (glTexture) {
    return glTexture;
  }
  auto eaglDevice = static_cast<EAGLDevice*>(context->device());
  if (eaglDevice == nullptr) {
    return nullptr;
  }

  auto format = CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_OneComponent8
                    ? PixelFormat::ALPHA_8
                    : PixelFormat::BGRA_8888;
  auto texture = GetTextureRef(context, pixelBuffer, format, eaglDevice->getTextureCache());
  if (texture == nil) {
    return nullptr;
  }
  auto sampler = std::make_unique<GLSampler>();
  sampler->format = format;
  sampler->target = CVOpenGLESTextureGetTarget(texture);
  sampler->id = CVOpenGLESTextureGetName(texture);
  glTexture = Resource::AddToCache(context, new EAGLHardwareTexture(pixelBuffer), scratchKey);
  glTexture->sampler = std::move(sampler);
  glTexture->texture = texture;
  return glTexture;
}

ScratchKey EAGLHardwareTexture::ComputeScratchKey(CVPixelBufferRef pixelBuffer) {
  static const uint32_t HardwareType = UniqueID::Next();
  BytesKey bytesKey(3);
  bytesKey.write(HardwareType);
  // The pointer can be used as the key directly because the cache holder retains the CVPixelBuffer.
  // As long as the holder cache exists, the CVPixelBuffer pointer remains valid, avoiding conflicts
  // with new objects. In other scenarios, it's best to avoid using pointers as keys.
  bytesKey.write(pixelBuffer);
  return bytesKey;
}

EAGLHardwareTexture::EAGLHardwareTexture(CVPixelBufferRef pixelBuffer)
    : Texture(static_cast<int>(CVPixelBufferGetWidth(pixelBuffer)),
              static_cast<int>(CVPixelBufferGetHeight(pixelBuffer)), ImageOrigin::TopLeft),
      pixelBuffer(pixelBuffer) {
  CFRetain(pixelBuffer);
}

EAGLHardwareTexture::~EAGLHardwareTexture() {
  CFRelease(pixelBuffer);
  if (texture) {
    CFRelease(texture);
  }
}

size_t EAGLHardwareTexture::memoryUsage() const {
  return CVPixelBufferGetDataSize(pixelBuffer);
}

void EAGLHardwareTexture::onReleaseGPU() {
  if (texture == nil) {
    return;
  }
  static_cast<EAGLDevice*>(context->device())->releaseTexture(texture);
  texture = nil;
}
}  // namespace tgfx
