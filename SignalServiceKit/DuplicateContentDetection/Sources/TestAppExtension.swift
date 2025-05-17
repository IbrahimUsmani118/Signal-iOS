import UIKit

/// Extension with methods to integrate the duplicate content detection test UI
public class DuplicateContentDetectionTestApp {
    
    /// Shows the duplicate content detection test UI
    /// - Parameter viewController: The view controller to present from
    public static func showTestUI(from viewController: UIViewController) {
        // Configure the logger first
        Logger.configure()
        
        // Create the test UI
        let testVC = DuplicateContentDetectionViewController()
        let navController = UINavigationController(rootViewController: testVC)
        
        // Present the UI
        navController.modalPresentationStyle = .fullScreen
        viewController.present(navController, animated: true)
    }
    
    /// Adds a test button to the provided view controller
    /// - Parameter viewController: The view controller to add the button to
    public static func addTestButton(to viewController: UIViewController) {
        let button = UIButton(type: .system)
        button.setTitle("Test Duplicate Detection", for: .normal)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        
        button.translatesAutoresizingMaskIntoConstraints = false
        viewController.view.addSubview(button)
        
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor, constant: -20),
            button.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            button.widthAnchor.constraint(equalToConstant: 200),
            button.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        button.addTarget(viewController, action: #selector(DuplicateContentDetectionTestApp.launchTestUI(_:)), for: .touchUpInside)
    }
    
    /// Launches the test UI (for use with #selector)
    @objc public static func launchTestUI(_ sender: UIButton) {
        if let viewController = sender.findViewController() {
            showTestUI(from: viewController)
        }
    }
}

// MARK: - Helper Extensions

extension UIView {
    /// Finds the view controller that owns this view
    fileprivate func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let nextResponder = responder?.next {
            if let viewController = nextResponder as? UIViewController {
                return viewController
            }
            responder = nextResponder
        }
        return nil
    }
}

// MARK: - For SwiftUI Integration

#if canImport(SwiftUI)
import SwiftUI

@available(iOS 13.0, *)
public struct DuplicateContentDetectionTestView: UIViewControllerRepresentable {
    public init() {}
    
    public func makeUIViewController(context: Context) -> UIViewController {
        return DuplicateContentDetectionViewController()
    }
    
    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Nothing to update
    }
}
#endif 