//
//  ContentView.swift
//  NeuroEditorSUI
//
//  Created by Natalia Sinitsyna on 23.11.2024.
//

import SwiftUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

struct NeuroFaceEditorView: View {
    @State private var inputImage: UIImage?
    @State private var outputImage: UIImage?
    @State private var showingImagePicker = false
    @State private var faceObservations: [VNFaceObservation] = []
    
    @State private var ovalScale: CGFloat = 1.0
    @State private var eyeScale: CGFloat = 1.0
    @State private var noseScale: CGFloat = 1.0
    
    var body: some View {
        VStack {
            Text("Нейро-Фейс Редактор")
                .font(.largeTitle)
                .bold()
                .padding()
            
            Spacer()
            
            if let outputImage = outputImage {
                Image(uiImage: outputImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 300)
                    .cornerRadius(10)
                    .shadow(radius: 5)
            } else {
                Rectangle()
                    .fill(Color.secondary)
                    .frame(height: 300)
                    .cornerRadius(10)
                    .shadow(radius: 5)
                    .overlay(
                        Text("Выберите изображение")
                            .foregroundColor(.white)
                            .bold()
                    )
            }
            
            Spacer()
            
            Group {
                HStack {
                    Text("Овал лица")
                    Slider(value: $ovalScale, in: 0.5...2.0, step: 0.1)
                        .onChange(of: ovalScale) { _, _ in transformFace() }
                }
                HStack {
                    Text("Глаза")
                    Slider(value: $eyeScale, in: 0.5...2.0, step: 0.1)
                        .onChange(of: eyeScale) { _, _ in transformFace() }
                }
                HStack {
                    Text("Нос")
                    Slider(value: $noseScale, in: 0.5...2.0, step: 0.1)
                        .onChange(of: noseScale) { _, _ in transformFace() }
                }
            }
            .padding()
            
            Button("Выбрать изображение") {
                showingImagePicker = true
            }
            .padding()
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $inputImage, onImagePicked: detectFace)
        }
    }
    
    func detectFace() {
        guard let inputImage = inputImage else {
            print("Изображение отсутствует")
            return }
        
        // Vision request for face detection
        let request = VNDetectFaceLandmarksRequest { request, error in
            if let error = error {
                print("Ошибка Vision: \(error.localizedDescription)")
                return
            }
            
            if let results = request.results as? [VNFaceObservation] {
                if results.isEmpty {
                    print("Лица не обнаружены")
                } else {
                    print("Найдено лиц: \(results.count)")
                }
                self.faceObservations = results
                transformFace()
            }
        }
        
        let handler = VNImageRequestHandler(cgImage: inputImage.cgImage!, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("Ошибка Vision: \(error.localizedDescription)")
        }
    }
    
    func transformFace() {
        guard let inputImage = inputImage else {
            print("Отсутствует исходное изображение")
            return
        }
        
        let ciImage = CIImage(image: inputImage)
        let context = CIContext()
        var transformedImage = ciImage
        
        for face in faceObservations {
            // Применяем модификацию овала лица
            transformedImage = modifyOval(of: transformedImage!, faceObservation: face, scaleX: ovalScale, scaleY: ovalScale)
            
            // Применяем изменения глаз
            transformedImage = modifyEyes(of: transformedImage!, faceObservation: face, eyeScale: eyeScale)
            
            // Применяем изменения носа
                    transformedImage = modifyNose(of: transformedImage!, faceObservation: face, noseScale: noseScale)
        }
        
        // Обновляем outputImage
        if let cgImage = context.createCGImage(transformedImage!, from: transformedImage!.extent) {
            self.outputImage = UIImage(cgImage: cgImage)
        }
    }
    
    func applyTransformation(to image: CIImage, points: [CGPoint], in boundingBox: CGRect, scale: CGFloat) -> CIImage {
        var transformedImage = image
        
        // Размеры изображения
        let imageWidth = image.extent.width
        let imageHeight = image.extent.height
        
        for point in points {
            // Перевод нормализованных координат Vision в координаты Core Image
            let transformedPoint = CGPoint(
                x: boundingBox.minX * imageWidth + point.x * boundingBox.width * imageWidth,
                y: imageHeight - (boundingBox.minY * imageHeight + point.y * boundingBox.height * imageHeight) // Инвертируем ось Y
            )
            
            let filter = CIFilter.bumpDistortion()
            filter.center = transformedPoint
            filter.scale = Float(scale)
            filter.radius = 50
            filter.inputImage = transformedImage
            
            if let output = filter.outputImage {
                transformedImage = output
            }
        }
        
        return transformedImage
    }
    
    func modifyOval(of image: CIImage, faceObservation: VNFaceObservation, scaleX: CGFloat, scaleY: CGFloat) -> CIImage {
        var transformedImage = image
        
        // Размеры изображения
        let imageWidth = image.extent.width
        let imageHeight = image.extent.height
        
        // Центр boundingBox
        let boundingBox = faceObservation.boundingBox
        let center = CGPoint(
            x: boundingBox.midX * imageWidth,
            y: imageHeight - boundingBox.midY * imageHeight // Инверсия оси Y
        )
        
        // Радиус для трансформации (основан на размере лица)
        let radius = min(boundingBox.width * imageWidth, boundingBox.height * imageHeight)*0.9
        
        // Фильтр для деформации
        let filter = CIFilter.bumpDistortionLinear()
        filter.center = center
        filter.radius = Float(radius)
        filter.scale = Float(scaleX) // Используем горизонтальное сжатие/растяжение
        filter.inputImage = transformedImage
        
        if let output = filter.outputImage {
            transformedImage = output
        }
        
        return transformedImage
    }
    
    func modifyEyes(of image: CIImage, faceObservation: VNFaceObservation, eyeScale: CGFloat) -> CIImage {
        var transformedImage = image

        // Размеры изображения
        let imageWidth = image.extent.width
        let imageHeight = image.extent.height

        // Функция для трансформации одного глаза
        func transformEye(_ eye: VNFaceLandmarkRegion2D) {
            // Центр глаза
            let eyeCenter = eye.normalizedPoints.reduce(CGPoint.zero) { partialResult, point in
                CGPoint(
                    x: partialResult.x + point.x,
                    y: partialResult.y + point.y
                )
            }.applying(CGAffineTransform(scaleX: 1 / CGFloat(eye.pointCount), y: 0.8 / CGFloat(eye.pointCount)))

            // Преобразуем нормализованные координаты центра глаза в координаты изображения
            let transformedCenter = CGPoint(
                x: (faceObservation.boundingBox.minX + eyeCenter.x * faceObservation.boundingBox.width) * imageWidth,
                y: imageHeight - (faceObservation.boundingBox.minY + eyeCenter.y * faceObservation.boundingBox.height) * imageHeight // Инверсия Y
            )

            // Радиус области трансформации
            let eyeRadius = faceObservation.boundingBox.width * imageWidth * 0.15

            // Применяем фильтр
            let filter = CIFilter.bumpDistortion()
            filter.center = transformedCenter
            filter.radius = Float(eyeRadius)
            filter.scale = Float(eyeScale)
            filter.inputImage = transformedImage

            if let output = filter.outputImage {
                transformedImage = output
            }
        }

        // Применяем трансформацию для обоих глаз
        if let leftEye = faceObservation.landmarks?.leftEye {
            transformEye(leftEye)
        }
        if let rightEye = faceObservation.landmarks?.rightEye {
            transformEye(rightEye)
        }

        return transformedImage
    }
    
    func modifyNose(of image: CIImage, faceObservation: VNFaceObservation, noseScale: CGFloat) -> CIImage {
        var transformedImage = image

        // Размеры изображения
        let imageWidth = image.extent.width
        let imageHeight = image.extent.height

        guard let nose = faceObservation.landmarks?.nose else {
            print("Нос не найден")
            return transformedImage
        }
        
        for point in nose.normalizedPoints {
            let pixelPoint = CGPoint(
                x: (faceObservation.boundingBox.minX + point.x * faceObservation.boundingBox.width) * imageWidth,
                y: imageHeight - (faceObservation.boundingBox.minY + point.y * faceObservation.boundingBox.height) * imageHeight
            )
            print("Нормализованные координаты: \(point), Пиксельные координаты: \(pixelPoint)")
        }

        // Центр носа
        let noseCenter = nose.normalizedPoints.reduce(CGPoint.zero) { partialResult, point in
            CGPoint(
                x: partialResult.x + point.x,
                y: partialResult.y + point.y
            )
        }.applying(CGAffineTransform(scaleX: 1 / CGFloat(nose.pointCount), y: 1.7 / CGFloat(nose.pointCount)))

        // Преобразуем нормализованные координаты центра носа в координаты изображения
        let transformedCenter = CGPoint(
            x: (faceObservation.boundingBox.minX + noseCenter.x * faceObservation.boundingBox.width) * imageWidth,
            y: imageHeight - (faceObservation.boundingBox.minY + noseCenter.y * faceObservation.boundingBox.height) * imageHeight // Инверсия оси Y
        )

        // Радиус области трансформации носа
        let noseRadius = faceObservation.boundingBox.width * imageWidth * 0.15

        // Применяем фильтр
        let filter = CIFilter.bumpDistortion()
        filter.center = transformedCenter
        filter.radius = Float(noseRadius)
        filter.scale = Float(noseScale)
        filter.inputImage = transformedImage

        if let output = filter.outputImage {
            transformedImage = output
        }

        return transformedImage
    }
}
