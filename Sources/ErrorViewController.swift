//
//  ErrorViewController.swift
//  SkyApp
//
//  加载失败提示页。由 WebViewController 作为子控制器覆盖显示。
//

import UIKit

final class ErrorViewController: UIViewController {

    // MARK: - Public properties

    /// 点击「重试」后触发的回调，由外部注入。
    var onRetry: (() -> Void)?

    // MARK: - Private properties

    private let message: String

    private let iconContainer = UIView()
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let buttonContainer = UIView()

    // MARK: - Init

    init(message: String) {
        self.message = message
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        configureIcon()
        configureLabels()
        configureRetryButton()
        layoutContent()
    }

    // MARK: - Configuration

    private func configureIcon() {
        iconImageView.image = UIImage(systemName: "wifi.exclamationmark")
        iconImageView.tintColor = .secondaryLabel
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false

        // StackView 使用 .fill 对齐，直接放固定宽度的图片会被拉伸，
        // 因此外面包一层容器，由容器撑满宽度、图片居中固定尺寸。
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconImageView)

        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 56.0),
            iconImageView.heightAnchor.constraint(equalToConstant: 56.0),
            iconImageView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconImageView.topAnchor.constraint(equalTo: iconContainer.topAnchor),
            iconImageView.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor)
        ])
    }

    private func configureLabels() {
        titleLabel.text = "加载失败"
        titleLabel.font = UIFont.systemFont(ofSize: 20.0, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1

        messageLabel.text = message
        messageLabel.font = UIFont.systemFont(ofSize: 14.0, weight: .regular)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
    }

    private func configureRetryButton() {
        retryButton.setTitle("重试", for: .normal)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.titleLabel?.font = UIFont.systemFont(ofSize: 16.0, weight: .semibold)
        retryButton.backgroundColor = AppConfig.primaryColor
        retryButton.layer.cornerRadius = 12.0
        retryButton.clipsToBounds = true
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        retryButton.translatesAutoresizingMaskIntoConstraints = false

        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.addSubview(retryButton)

        NSLayoutConstraint.activate([
            retryButton.widthAnchor.constraint(equalToConstant: 160.0),
            retryButton.heightAnchor.constraint(equalToConstant: 44.0),
            retryButton.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor),
            retryButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            retryButton.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor)
        ])
    }

    private func layoutContent() {
        let stackView = UIStackView(arrangedSubviews: [iconContainer,
                                                       titleLabel,
                                                       messageLabel,
                                                       buttonContainer])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = 16.0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32.0),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32.0),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    // MARK: - Actions

    @objc private func retryTapped() {
        onRetry?()
    }
}
