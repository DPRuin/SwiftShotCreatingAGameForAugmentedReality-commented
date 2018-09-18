/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Maps saving and loading methods for the Game Scene View Controller.
地图保存与加载
*/

import UIKit
import ARKit
import os.log

extension GameViewController {
    
    // MARK: - Relocalization Help
    
    func configureRelocalizationHelp() {
        if UserDefaults.standard.showARRelocalizationHelp {
            switch sessionState {
            case .lookingForSurface, .placingBoard, .adjustingBoard:
                showRelocalizationHelp(isClient: false)
                return
            case .localizingToBoard:
                if let anchor = targetWorldMap?.keyPositionAnchors.first {
                    showRelocalizationHelp(isClient: true)
                    setKeyPositionThumbnail(image: anchor.image)
                }
            default:
                hideRelocalizationHelp()
                return
            }
        } else {
            hideRelocalizationHelp()
        }
    }
    
    private func showRelocalizationHelp(isClient: Bool) {
        if !isClient {
            saveAsKeyPositionButton.isHidden = false
        } else {
            keyPositionThumbnail.isHidden = false
            nextKeyPositionThumbnailButton.isHidden = false
            previousKeyPositionThumbnailButton.isHidden = false
        }
    }
    
    private func hideRelocalizationHelp() {
        keyPositionThumbnail.isHidden = true
        saveAsKeyPositionButton.isHidden = true
        nextKeyPositionThumbnailButton.isHidden = true
        previousKeyPositionThumbnailButton.isHidden = true
    }
    
    private func setKeyPositionThumbnail(image: UIImage) {
        keyPositionThumbnail.image = image
    }
    
    @IBAction func saveKeyPositionPressed(_ sender: Any) {
        // Save the current position as an ARAnchor and store it in the worldmap for later use when re-localizing to guide users
        // 保存当前位置作为一个 ARAnchor 并将其储存到世界地图中，以便以后在重新本地化时指导用户
        var image: UIImage?
        var pose: float4x4?
        var mappingStatus: ARFrame.WorldMappingStatus = .notAvailable
        
        if let currentFrame = sceneView.session.currentFrame {
            image = sceneView.createScreenshot(interfaceOrientation: UIDevice.current.orientation)
            pose = currentFrame.camera.transform
            mappingStatus = currentFrame.worldMappingStatus
        }
        
        // Add key position anchor to the scene
        // 向场景中添加关键位置锚点
        if pose != nil && image != nil {
            let newKeyPosition = KeyPositionAnchor(image: image!, transform: pose!, mappingStatus: mappingStatus)
            sceneView.session.add(anchor: newKeyPosition)
        }
    }
    
    @IBAction func showNextKeyPositionThumbnail(_ sender: Any) {
        guard let image = keyPositionThumbnail.image else {
            return
        }
        
        // Get the key position anchors from the current world map
        // 从当前世界地图中拿到关键位置锚点
        guard let keyPositionAnchors = targetWorldMap?.keyPositionAnchors else {
            return
        }
        
        // Get the current key position anchor displayed
        // 拿到显示出的当前关键位置锚点
        guard let currentKeyPositionAnchor = keyPositionAnchors.first(where: { $0.image == image }) else {
            return
        }
        
        if let currentIndex = keyPositionAnchors.index(of: currentKeyPositionAnchor) {
            let nextIndex = (currentIndex + 1) % keyPositionAnchors.count
            setKeyPositionThumbnail(image: keyPositionAnchors[nextIndex].image)
        }
        
    }
    
    @IBAction func showPreviousKeyPositionThumbnail(_ sender: Any) {
        guard let image = keyPositionThumbnail.image else {
            return
        }
        
        // Get the key position anchors from the current world map
        // 从当前世界地图中拿到关键位置锚点
        guard let keyPositionAnchors = targetWorldMap?.keyPositionAnchors else {
            return
        }
        
        // Get the current key position anchor displayed
        // 拿到显示出的当前关键位置锚点
        guard let currentKeyPositionAnchor = keyPositionAnchors.first(where: { $0.image == image }) else {
            return
        }
        
        if let currentIndex = keyPositionAnchors.index(of: currentKeyPositionAnchor) {
            var nextIndex = currentIndex
            if currentIndex == 0 && keyPositionAnchors.count > 1 {
                nextIndex = keyPositionAnchors.count - 1
            } else if currentIndex - 1 >= 0 {
                nextIndex = currentIndex - 1
            } else {
                nextIndex = 0
            }
            setKeyPositionThumbnail(image: keyPositionAnchors[nextIndex].image)
        }
    }
    
    // MARK: Saving and Loading Maps
    
    func configureMappingUI() {
        let showMappingState = sessionState != .gameInProgress &&
            sessionState != .setup &&
            sessionState != .localizingToBoard &&
            UserDefaults.standard.showARDebug
        
        mappingStateLabel.isHidden = !showMappingState
        saveButton.isHidden = sessionState == .setup
        loadButton.isHidden = sessionState == .setup
    }
    
    func updateMappingStatus(_ mappingStatus: ARFrame.WorldMappingStatus) {
        // Check the mapping status of the worldmap to be able to save the worldmap when in a good state
        // 检查世界地图的构建状态，完成时可以保存世界地图
        switch mappingStatus {
        case .notAvailable:
            mappingStateLabel.text = "Mapping state: Not Available"
            mappingStateLabel.textColor = .red
            saveAsKeyPositionButton.isEnabled = false
            saveButton.isEnabled = false
        case .limited:
            mappingStateLabel.text = "Mapping state: Limited"
            mappingStateLabel.textColor = .red
            saveAsKeyPositionButton.isEnabled = false
            saveButton.isEnabled = false
        case .extending:
            mappingStateLabel.text = "Mapping state: Extending"
            mappingStateLabel.textColor = .red
            saveAsKeyPositionButton.isEnabled = false
            saveButton.isEnabled = false
        case .mapped:
            mappingStateLabel.text = "Mapping state: Mapped"
            mappingStateLabel.textColor = .green
            saveAsKeyPositionButton.isEnabled = true
            saveButton.isEnabled = true
        }
    }
    
    func getCurrentWorldMapData(_ closure: @escaping (Data?, Error?) -> Void) {
        os_log(.info, "in getCurrentWordMapData")
        // When loading a map, send the loaded map and not the current extended map
        // 当正在加载地图时，发送已加载的地图，而不是当前扩展过的地图
        if let targetWorldMap = targetWorldMap {
            os_log(.info, "using existing worldmap, not asking session for a new one.")
            compressMap(map: targetWorldMap, closure)
            return
        } else {
            os_log(.info, "asking ARSession for the world map")
            sceneView.session.getCurrentWorldMap { map, error in
                os_log(.info, "ARSession getCurrentWorldMap returned")
                if let error = error {
                    os_log(.error, "didn't work! %s", "\(error)")
                    closure(nil, error)
                }
                guard let map = map else { os_log(.error, "no map either!"); return }
                os_log(.info, "got a worldmap, compressing it")
                self.compressMap(map: map, closure)
            }
        }
    }
    
    @IBAction func savePressed(_ sender: Any) {
        activityIndicator.startAnimating()
        getCurrentWorldMapData { data, error in
            DispatchQueue.main.async {
                self.activityIndicator.stopAnimating()
                if let error = error as NSError? {
                    let title = error.localizedDescription
                    let message = error.localizedFailureReason
                    self.showAlert(title: title, message: message)
                    return
                }
                
                guard let data = data else { os_log(.error, "no data"); return }
                self.showSaveDialog(for: data)
            }
        }
    }
    
    @IBAction func loadPressed(_ sender: Any) {
        let typeIdentifier = Bundle.main.bundleIdentifier! + ".worldmap"
        let picker = UIDocumentPickerViewController(documentTypes: [typeIdentifier], in: .open)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        present(picker, animated: true, completion: nil)
    }
    
    private func showSaveDialog(for data: Data) {
        let dialog = UIAlertController(title: "Save World Map", message: nil, preferredStyle: .alert)
        dialog.addTextField(configurationHandler: nil)
        let saveAction = UIAlertAction(title: "Save", style: .default) { action in
            guard let fileName = dialog.textFields?.first?.text else {
                os_log(.error, "no filename"); return
            }
            DispatchQueue.global(qos: .background).async {
                do {
                    let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    let maps = docs.appendingPathComponent("maps", isDirectory: true)
                    try FileManager.default.createDirectory(at: maps, withIntermediateDirectories: true, attributes: nil)
                    let targetURL = maps.appendingPathComponent(fileName).appendingPathExtension("swiftshotmap")
                    try data.write(to: targetURL, options: [.atomic])
                    DispatchQueue.main.async {
                        self.showAlert(title: "Saved")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.showAlert(title: error.localizedDescription, message: nil)
                    }
                }
            }
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        dialog.addAction(saveAction)
        dialog.addAction(cancelAction)
        
        present(dialog, animated: true, completion: nil)
    }
    
    /// Get the archived data from a URL Path
    /// 从一个 URL 路径拿到压缩过的数据
    private func fetchArchivedWorldMap(from url: URL, _ closure: @escaping (Data?, Error?) -> Void) {
        DispatchQueue.global().async {
            do {
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                let data = try Data(contentsOf: url)
                closure(data, nil)
                
            } catch {
                DispatchQueue.main.async {
                    self.showAlert(title: error.localizedDescription)
                }
                closure(nil, error)
            }
        }
    }
    
    private func compressMap(map: ARWorldMap, _ closure: @escaping (Data?, Error?) -> Void) {
        DispatchQueue.global().async {
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                os_log(.info, "data size is %d", data.count)
                let compressedData = data.compressed()
                os_log(.info, "compressed size is %d", compressedData.count)
                closure(compressedData, nil)
            } catch {
                os_log(.error, "archiving failed %s", "\(error)")
                closure(nil, error)
            }
        }
    }
}

extension GameViewController: UIDocumentPickerDelegate {
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        os_log(.info, "Selected external WorldMap")
        guard let selected = urls.first else { return }
        fetchArchivedWorldMap(from: selected, { data, error in
            if let error = error {
                os_log(.error, "Failed to load the external WorldMap! %s", "\(error)")
                return
            }
            guard let data = data else { os_log(.error, "No data received while loading an external WorldMap"); return }
            self.loadWorldMap(from: data)
        })
    }
}
