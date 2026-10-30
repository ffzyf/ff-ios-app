//
//  WebViewController.swift
//  SkyApp
//
//  核心控制器：把一个站点封装成 WKWebView 页面。
//  仅使用 iOS 15 起稳定存在的 UIKit / WebKit API。
//

import UIKit
import WebKit

final class WebViewController: UIViewController {

    // MARK: - Constants

    /// 错误覆盖层的识别 tag，用于避免重复弹出。
    private static let errorViewTag: Int = 9901

    /// 固定 User-Agent 前缀。故意不使用 KVC 读取私有 userAgent 属性，降低崩溃与审核风险。
    private static let baseUserAgent: String = "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1"

    // MARK: - Stored properties

    private let tab: AppTab

    /// 只在 viewDidLoad 中创建一次，故使用隐式解包可选值。
    private var webView: WKWebView!

    private let progressView = UIProgressView(progressViewStyle: .bar)

    private var progressObservation: NSKeyValueObservation?

    /// 是否已经发起过首次加载，用于避免重复 load。
    private var hasLoadedOnce = false

    // MARK: - Init

    init(tab: AppTab) {
        self.tab = tab
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        progressObservation?.invalidate()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        setupWebView()
        setupProgressView()
        setupProgressObservation()

        title = tab.title

        if hasLoadedOnce == false {
            loadStartURL()
        }
    }

    // MARK: - Setup

    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        // 视频内联播放（不全屏接管）。
        configuration.allowsInlineMediaPlayback = true
        // 允许自动播放，无需用户手势。
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // 共享 Cookie / localStorage。
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        // 允许页面执行 JavaScript。
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.customUserAgent = WebViewController.baseUserAgent + AppConfig.customUserAgentSuffix

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        self.webView = webView
    }

    private func setupProgressView() {
        progressView.progressTintColor = AppConfig.primaryColor
        progressView.trackTintColor = .clear
        progressView.isHidden = true
        progressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressView)

        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2.0)
        ])
    }

    private func setupProgressObservation() {
        // 显式写出根类型，避免隐式解包属性参与 keyPath 推断时出现歧义。
        progressObservation = webView.observe(\WKWebView.estimatedProgress, options: [.new]) { [weak self] observedWebView, _ in
            let progress = observedWebView.estimatedProgress
            DispatchQueue.main.async {
                self?.updateProgress(progress)
            }
        }
    }

    // MARK: - Actions

    @objc private func handleRefresh() {
        webView.reload()
    }

    // MARK: - Loading

    private func loadStartURL() {
        guard let url = URL(string: tab.urlString) else { return }

        let request = URLRequest(url: url,
                                 cachePolicy: .useProtocolCachePolicy,
                                 timeoutInterval: 30.0)
        webView.load(request)
        hasLoadedOnce = true
    }

    private func updateProgress(_ value: Double) {
        let clampedValue = max(0.0, min(1.0, value))
        progressView.progress = Float(clampedValue)

        if clampedValue >= 1.0 {
            progressView.isHidden = true
        } else {
            progressView.isHidden = false
        }
    }

    /// 以覆盖视图的方式展示错误页（不用模态，避免 dismiss 时序问题）。
    private func showErrorIfNeeded(_ error: Error) {
        // 已经显示过错误页则不重复添加。
        if view.viewWithTag(WebViewController.errorViewTag) != nil {
            return
        }

        let errorViewController = ErrorViewController(message: error.localizedDescription)
        errorViewController.onRetry = { [weak self] in
            guard let self = self else { return }
            self.dismissErrorIfNeeded()
            self.webView.reload()
        }

        addChild(errorViewController)
        errorViewController.view.tag = WebViewController.errorViewTag
        errorViewController.view.frame = view.bounds
        errorViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(errorViewController.view)
        errorViewController.didMove(toParent: self)
    }

    /// 移除错误覆盖层并摘除子控制器（避免 children 只增不减）。
    private func dismissErrorIfNeeded() {
        guard let overlay = view.viewWithTag(WebViewController.errorViewTag) else { return }
        overlay.removeFromSuperview()
        children
            .filter { $0.viewIfLoaded?.tag == WebViewController.errorViewTag }
            .forEach { $0.removeFromParent() }
    }
}

// MARK: - WKNavigationDelegate

extension WebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.scrollView.refreshControl?.endRefreshing()
        progressView.isHidden = true
        dismissErrorIfNeeded()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        webView.scrollView.refreshControl?.endRefreshing()
        progressView.isHidden = true

        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }
        showErrorIfNeeded(error)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        webView.scrollView.refreshControl?.endRefreshing()
        progressView.isHidden = true

        let nsError = error as NSError
        // -999 (NSURLErrorCancelled) 是正常的导航取消，不提示错误。
        if nsError.code == NSURLErrorCancelled {
            return
        }
        showErrorIfNeeded(error)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let scheme = (url.scheme ?? "").lowercased()
        // 网页自身可处理的协议（含 javascript:，站点常用在 href 上）。
        if ["http", "https", "about", "file", "blob", "data", "javascript"].contains(scheme) {
            decisionHandler(.allow)
            return
        }
        // 交由系统 App 处理的协议。注意：不用 canOpenURL（它对未登记 LSApplicationQueriesSchemes
        // 的 scheme 恒返回 false，会误杀 tel/mailto）。
        if ["tel", "mailto", "sms", "itms-apps", "itms", "weixin", "alipay"].contains(scheme) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        decisionHandler(.cancel)
    }
}

// MARK: - WKUIDelegate

extension WebViewController: WKUIDelegate {

    /// 处理 target="_blank" 等新窗口请求：在当前 WebView 内打开。
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
