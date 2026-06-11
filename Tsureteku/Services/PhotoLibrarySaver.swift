//
//  PhotoLibrarySaver.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/10.
//

import Photos
import UIKit

enum PhotoLibrarySaver {
    enum SaveError: LocalizedError {
        case denied
        case failed

        var errorDescription: String? {
            switch self {
            case .denied:
                "写真への保存が許可されていません。"
            case .failed:
                "写真を保存できませんでした。"
            }
        }
    }

    static func save(_ image: UIImage, completion: @escaping (Result<Void, Error>) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        switch status {
        case .authorized, .limited:
            performSave(image, completion: completion)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                guard newStatus == .authorized || newStatus == .limited else {
                    DispatchQueue.main.async {
                        completion(.failure(SaveError.denied))
                    }
                    return
                }

                performSave(image, completion: completion)
            }
        case .denied, .restricted:
            completion(.failure(SaveError.denied))
        @unknown default:
            completion(.failure(SaveError.denied))
        }
    }

    private static func performSave(_ image: UIImage, completion: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(error))
                } else if success {
                    completion(.success(()))
                } else {
                    completion(.failure(SaveError.failed))
                }
            }
        }
    }
}
