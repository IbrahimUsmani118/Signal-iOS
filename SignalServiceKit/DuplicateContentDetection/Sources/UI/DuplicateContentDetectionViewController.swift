import UIKit

public class DuplicateContentDetectionViewController: UIViewController {
    
    // UI Elements
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let titleLabel = UILabel()
    private let imageView = UIImageView()
    private let selectImageButton = UIButton(type: .system)
    private let checkDuplicateButton = UIButton(type: .system)
    private let blockImageButton = UIButton(type: .system)
    private let textInputField = UITextView()
    private let checkTextButton = UIButton(type: .system)
    private let resultLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let verifyServicesButton = UIButton(type: .system)
    
    private let imagePicker = UIImagePickerController()
    
    // Logic
    private let example = DuplicateContentDetectionExample()
    private var selectedImage: UIImage?
    
    // MARK: - Lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupLayout()
        setupActions()
    }
    
    // MARK: - UI Setup
    
    private func setupViews() {
        title = "Duplicate Content Detection"
        view.backgroundColor = .systemBackground
        
        titleLabel.text = "Duplicate Content Detection Test"
        titleLabel.font = UIFont.boldSystemFont(ofSize: 22)
        titleLabel.textAlignment = .center
        
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .secondarySystemBackground
        imageView.layer.cornerRadius = 8
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = UIColor.systemGray.cgColor
        imageView.clipsToBounds = true
        
        selectImageButton.setTitle("Select Image", for: .normal)
        selectImageButton.backgroundColor = .systemBlue
        selectImageButton.setTitleColor(.white, for: .normal)
        selectImageButton.layer.cornerRadius = 8
        
        checkDuplicateButton.setTitle("Check Duplicate", for: .normal)
        checkDuplicateButton.backgroundColor = .systemGreen
        checkDuplicateButton.setTitleColor(.white, for: .normal)
        checkDuplicateButton.layer.cornerRadius = 8
        checkDuplicateButton.isEnabled = false
        
        blockImageButton.setTitle("Block Image", for: .normal)
        blockImageButton.backgroundColor = .systemRed
        blockImageButton.setTitleColor(.white, for: .normal)
        blockImageButton.layer.cornerRadius = 8
        blockImageButton.isEnabled = false
        
        textInputField.text = "Enter text to check for duplicates"
        textInputField.font = UIFont.systemFont(ofSize: 16)
        textInputField.backgroundColor = .secondarySystemBackground
        textInputField.layer.cornerRadius = 8
        textInputField.layer.borderWidth = 1
        textInputField.layer.borderColor = UIColor.systemGray.cgColor
        
        checkTextButton.setTitle("Check Text", for: .normal)
        checkTextButton.backgroundColor = .systemIndigo
        checkTextButton.setTitleColor(.white, for: .normal)
        checkTextButton.layer.cornerRadius = 8
        
        resultLabel.text = "Results will appear here"
        resultLabel.numberOfLines = 0
        resultLabel.textAlignment = .left
        resultLabel.font = UIFont.systemFont(ofSize: 14)
        resultLabel.backgroundColor = .tertiarySystemBackground
        resultLabel.layer.cornerRadius = 8
        resultLabel.layer.borderWidth = 1
        resultLabel.layer.borderColor = UIColor.systemGray.cgColor
        resultLabel.clipsToBounds = true
        
        verifyServicesButton.setTitle("Verify AWS Services", for: .normal)
        verifyServicesButton.backgroundColor = .systemOrange
        verifyServicesButton.setTitleColor(.white, for: .normal)
        verifyServicesButton.layer.cornerRadius = 8
        
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = .systemBlue
        
        imagePicker.allowsEditing = true
        imagePicker.delegate = self
        
        // Add views to the hierarchy
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(titleLabel)
        contentView.addSubview(imageView)
        contentView.addSubview(selectImageButton)
        contentView.addSubview(checkDuplicateButton)
        contentView.addSubview(blockImageButton)
        contentView.addSubview(textInputField)
        contentView.addSubview(checkTextButton)
        contentView.addSubview(resultLabel)
        contentView.addSubview(verifyServicesButton)
        contentView.addSubview(activityIndicator)
    }
    
    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        selectImageButton.translatesAutoresizingMaskIntoConstraints = false
        checkDuplicateButton.translatesAutoresizingMaskIntoConstraints = false
        blockImageButton.translatesAutoresizingMaskIntoConstraints = false
        textInputField.translatesAutoresizingMaskIntoConstraints = false
        checkTextButton.translatesAutoresizingMaskIntoConstraints = false
        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        verifyServicesButton.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // ScrollView
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            // ContentView
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Title Label
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Image View
            imageView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -40),
            imageView.heightAnchor.constraint(equalToConstant: 200),
            
            // Select Image Button
            selectImageButton.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 20),
            selectImageButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            selectImageButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            selectImageButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Check Duplicate Button
            checkDuplicateButton.topAnchor.constraint(equalTo: selectImageButton.bottomAnchor, constant: 10),
            checkDuplicateButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            checkDuplicateButton.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.5, constant: -25),
            checkDuplicateButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Block Image Button
            blockImageButton.topAnchor.constraint(equalTo: selectImageButton.bottomAnchor, constant: 10),
            blockImageButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            blockImageButton.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.5, constant: -25),
            blockImageButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Text Input Field
            textInputField.topAnchor.constraint(equalTo: blockImageButton.bottomAnchor, constant: 20),
            textInputField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            textInputField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            textInputField.heightAnchor.constraint(equalToConstant: 100),
            
            // Check Text Button
            checkTextButton.topAnchor.constraint(equalTo: textInputField.bottomAnchor, constant: 10),
            checkTextButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            checkTextButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            checkTextButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Result Label
            resultLabel.topAnchor.constraint(equalTo: checkTextButton.bottomAnchor, constant: 20),
            resultLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            resultLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            resultLabel.heightAnchor.constraint(equalToConstant: 150),
            
            // Verify Services Button
            verifyServicesButton.topAnchor.constraint(equalTo: resultLabel.bottomAnchor, constant: 20),
            verifyServicesButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            verifyServicesButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            verifyServicesButton.heightAnchor.constraint(equalToConstant: 44),
            verifyServicesButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            
            // Activity Indicator
            activityIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
    
    private func setupActions() {
        selectImageButton.addTarget(self, action: #selector(selectImageTapped), for: .touchUpInside)
        checkDuplicateButton.addTarget(self, action: #selector(checkDuplicateTapped), for: .touchUpInside)
        blockImageButton.addTarget(self, action: #selector(blockImageTapped), for: .touchUpInside)
        checkTextButton.addTarget(self, action: #selector(checkTextTapped), for: .touchUpInside)
        verifyServicesButton.addTarget(self, action: #selector(verifyServicesTapped), for: .touchUpInside)
    }
    
    // MARK: - Actions
    
    @objc private func selectImageTapped() {
        present(imagePicker, animated: true)
    }
    
    @objc private func checkDuplicateTapped() {
        guard let image = selectedImage else { return }
        startLoading()
        
        Task {
            let result = await example.checkForDuplicateImage(image)
            await MainActor.run {
                resultLabel.text = result
                stopLoading()
            }
        }
    }
    
    @objc private func blockImageTapped() {
        guard let image = selectedImage else { return }
        startLoading()
        
        Task {
            let result = await example.blockImage(image)
            await MainActor.run {
                resultLabel.text = result
                stopLoading()
            }
        }
    }
    
    @objc private func checkTextTapped() {
        let text = textInputField.text ?? ""
        if text.isEmpty || text == "Enter text to check for duplicates" {
            resultLabel.text = "Please enter some text first"
            return
        }
        
        startLoading()
        
        Task {
            let result = await example.checkForDuplicateText(text)
            await MainActor.run {
                resultLabel.text = result
                stopLoading()
            }
        }
    }
    
    @objc private func verifyServicesTapped() {
        startLoading()
        
        Task {
            let result = await example.verifyAWSServices()
            await MainActor.run {
                resultLabel.text = result
                stopLoading()
            }
        }
    }
    
    private func startLoading() {
        activityIndicator.startAnimating()
        selectImageButton.isEnabled = false
        checkDuplicateButton.isEnabled = false
        blockImageButton.isEnabled = false
        checkTextButton.isEnabled = false
        verifyServicesButton.isEnabled = false
    }
    
    private func stopLoading() {
        activityIndicator.stopAnimating()
        selectImageButton.isEnabled = true
        checkDuplicateButton.isEnabled = selectedImage != nil
        blockImageButton.isEnabled = selectedImage != nil
        checkTextButton.isEnabled = true
        verifyServicesButton.isEnabled = true
    }
}

// MARK: - UIImagePickerControllerDelegate

extension DuplicateContentDetectionViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let editedImage = info[.editedImage] as? UIImage {
            selectedImage = editedImage
            imageView.image = editedImage
        } else if let originalImage = info[.originalImage] as? UIImage {
            selectedImage = originalImage
            imageView.image = originalImage
        }
        
        checkDuplicateButton.isEnabled = selectedImage != nil
        blockImageButton.isEnabled = selectedImage != nil
        
        dismiss(animated: true)
    }
    
    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: true)
    }
} 