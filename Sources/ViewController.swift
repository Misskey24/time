import UIKit

final class ViewController: UIViewController {
    private let pipRenderer = PiPRenderer()
    private let displayLabel = UILabel()
    private let headerLabel = UILabel()
    private let sourceControl = UISegmentedControl(items: TimeSource.allCases.map { $0.rawValue })
    private let startButton = UIButton(type: .system)
    private let syncButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let metricsLabel = UILabel()
    private let dynamicIslandContainer = UIView()
    private let dynamicIslandTitleLabel = UILabel()
    private let dynamicIslandSwitch = UISwitch()
    private let pipPreview = UIView()
    private let hintLabel = UILabel()
    private var displayLink: CADisplayLink?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildUI()
        pipRenderer.onStatus = { [weak self] msg in
            DispatchQueue.main.async { self?.statusLabel.text = msg }
        }
        LiveActivityController.shared.onStatus = { [weak self] msg in
            DispatchQueue.main.async { self?.statusLabel.text = msg }
        }
        loadInitialSource()
        LiveActivityController.shared.restoreIfNeeded()
        PerformanceMetricsMonitor.shared.start()
        startInAppTicking()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 页面重新渲染布局时通知 renderer 更新内部图层边界
        pipRenderer.layoutDisplayLayer(in: pipPreview.bounds)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        pipRenderer.startTicking()
    }

    private func buildUI() {
        headerLabel.text = "时间悬浮秒表"
        headerLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        headerLabel.textColor = .white
        headerLabel.textAlignment = .center
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerLabel)

        sourceControl.translatesAutoresizingMaskIntoConstraints = false
        sourceControl.selectedSegmentIndex = TimeSource.allCases.firstIndex(of: StopwatchEngine.shared.source) ?? 0
        if #available(iOS 13.0, *) {
            sourceControl.selectedSegmentTintColor = UIColor(red: 0.2, green: 1.0, blue: 0.6, alpha: 1)
            sourceControl.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
            sourceControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        }
        sourceControl.addTarget(self, action: #selector(sourceChanged), for: .valueChanged)
        view.addSubview(sourceControl)

        displayLabel.translatesAutoresizingMaskIntoConstraints = false
        displayLabel.font = .monospacedDigitSystemFont(ofSize: 64, weight: .bold)
        displayLabel.textColor = UIColor(red: 0.2, green: 1.0, blue: 0.6, alpha: 1)
        displayLabel.textAlignment = .center
        displayLabel.attributedText = Self.makeDisplayText("00:00:00:0")
        displayLabel.adjustsFontSizeToFitWidth = true
        displayLabel.minimumScaleFactor = 0.5
        view.addSubview(displayLabel)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .lightGray
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        view.addSubview(statusLabel)

        metricsLabel.translatesAutoresizingMaskIntoConstraints = false
        metricsLabel.textColor = UIColor(white: 1, alpha: 0.82)
        metricsLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        metricsLabel.textAlignment = .center
        metricsLabel.numberOfLines = 2
        metricsLabel.adjustsFontSizeToFitWidth = true
        metricsLabel.minimumScaleFactor = 0.75
        metricsLabel.text = PerformanceMetricsMonitor.shared.snapshot.displayLine
        view.addSubview(metricsLabel)

        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.setTitle("启动悬浮窗", for: .normal)
        startButton.titleLabel?.font = .systemFont(ofSize: 22, weight: .semibold)
        startButton.setTitleColor(.black, for: .normal)
        startButton.backgroundColor = UIColor(red: 0.2, green: 1.0, blue: 0.6, alpha: 1)
        startButton.layer.cornerRadius = 14
        startButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 36, bottom: 14, right: 36)
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        view.addSubview(startButton)

        syncButton.translatesAutoresizingMaskIntoConstraints = false
        syncButton.setTitle("重新校时", for: .normal)
        syncButton.titleLabel?.font = .systemFont(ofSize: 16)
        syncButton.setTitleColor(.white, for: .normal)
        syncButton.layer.borderColor = UIColor.white.cgColor
        syncButton.layer.borderWidth = 1
        syncButton.layer.cornerRadius = 10
        syncButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 18, bottom: 8, right: 18)
        syncButton.addTarget(self, action: #selector(syncTapped), for: .touchUpInside)
        view.addSubview(syncButton)

        dynamicIslandContainer.translatesAutoresizingMaskIntoConstraints = false
        dynamicIslandContainer.backgroundColor = UIColor(white: 1, alpha: 0.08)
        dynamicIslandContainer.layer.cornerRadius = 12
        dynamicIslandContainer.layer.borderColor = UIColor(white: 1, alpha: 0.18).cgColor
        dynamicIslandContainer.layer.borderWidth = 1
        view.addSubview(dynamicIslandContainer)

        dynamicIslandTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        dynamicIslandTitleLabel.text = "显示时间到灵动岛"
        dynamicIslandTitleLabel.textColor = .white
        dynamicIslandTitleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        dynamicIslandContainer.addSubview(dynamicIslandTitleLabel)

        dynamicIslandSwitch.translatesAutoresizingMaskIntoConstraints = false
        dynamicIslandSwitch.onTintColor = UIColor(red: 0.2, green: 1.0, blue: 0.6, alpha: 1)
        dynamicIslandSwitch.isOn = LiveActivityController.shared.isEnabled
        dynamicIslandSwitch.addTarget(self, action: #selector(dynamicIslandSwitchChanged), for: .valueChanged)
        dynamicIslandContainer.addSubview(dynamicIslandSwitch)

        pipPreview.translatesAutoresizingMaskIntoConstraints = false
        pipPreview.backgroundColor = .black
        pipPreview.layer.cornerRadius = 10
        pipPreview.layer.masksToBounds = true
        pipPreview.layer.borderColor = UIColor.darkGray.cgColor
        pipPreview.layer.borderWidth = 1
        view.addSubview(pipPreview)
        
        pipRenderer.containerView.translatesAutoresizingMaskIntoConstraints = false
        pipPreview.addSubview(pipRenderer.containerView)

        // 【核心修复】移除了原先导致编译崩溃的错位嵌套方法名，回归标准属性平铺配置
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.text = "↑ 这是悬浮窗预览。点上面按钮进入画中画，再切到其他 App 即可悬浮。把窗口向屏幕边缘划，可以收成侧边。"
        hintLabel.textColor = .gray
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.numberOfLines = 0
        hintLabel.textAlignment = .center
        view.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            headerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            sourceControl.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 18),
            sourceControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            sourceControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            sourceControl.heightAnchor.constraint(equalToConstant: 36),

            displayLabel.topAnchor.constraint(equalTo: sourceControl.bottomAnchor, constant: 24),
            displayLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            displayLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            statusLabel.topAnchor.constraint(equalTo: displayLabel.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            metricsLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            metricsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            metricsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            startButton.topAnchor.constraint(equalTo: metricsLabel.bottomAnchor, constant: 20),
            startButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            syncButton.topAnchor.constraint(equalTo: startButton.bottomAnchor, constant: 14),
            syncButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            dynamicIslandContainer.topAnchor.constraint(equalTo: syncButton.bottomAnchor, constant: 18),
            dynamicIslandContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            dynamicIslandContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            dynamicIslandContainer.heightAnchor.constraint(equalToConstant: 54),

            dynamicIslandTitleLabel.leadingAnchor.constraint(equalTo: dynamicIslandContainer.leadingAnchor, constant: 16),
            dynamicIslandTitleLabel.centerYAnchor.constraint(equalTo: dynamicIslandContainer.centerYAnchor),

            dynamicIslandSwitch.trailingAnchor.constraint(equalTo: dynamicIslandContainer.trailingAnchor, constant: -14),
            dynamicIslandSwitch.centerYAnchor.constraint(equalTo: dynamicIslandContainer.centerYAnchor),
            dynamicIslandTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: dynamicIslandSwitch.leadingAnchor, constant: -12),

            pipPreview.topAnchor.constraint(equalTo: dynamicIslandContainer.bottomAnchor, constant: 22),
            pipPreview.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pipPreview.widthAnchor.constraint(equalToConstant: 280),
            pipPreview.heightAnchor.constraint(equalToConstant: 149),

            pipRenderer.containerView.topAnchor.constraint(equalTo: pipPreview.topAnchor),
            pipRenderer.containerView.leadingAnchor.constraint(equalTo: pipPreview.leadingAnchor),
            pipRenderer.containerView.trailingAnchor.constraint(equalTo: pipPreview.trailingAnchor),
            pipRenderer.containerView.bottomAnchor.constraint(equalTo: pipPreview.bottomAnchor),

            hintLabel.topAnchor.constraint(equalTo: pipPreview.bottomAnchor, constant: 10),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            hintLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
        ])
    }

    private func loadInitialSource() {
        statusLabel.text = "正在同步 \(StopwatchEngine.shared.source.rawValue) 时间…"
        StopwatchEngine.shared.setSource(StopwatchEngine.shared.source) { [weak self] ok in
            let src = StopwatchEngine.shared.source.rawValue
            self?.statusLabel.text = ok ? "已同步 \(src) 时间" : "\(src) 校时失败，使用本地时间"
            Task { @MainActor in
                LiveActivityController.shared.refreshIfEnabled()
            }
        }
    }

    private func startInAppTicking() {
        displayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(refreshDisplay))
        if #available(iOS 15.0, *) {
            let maxFPS = Float(PerformanceMetricsMonitor.maximumSupportedFrameRate)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: maxFPS, preferred: 0)
        } else {
            link.preferredFramesPerSecond = 0
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func refreshDisplay() {
        displayLabel.attributedText = Self.makeDisplayText(StopwatchEngine.shared.formattedTime())
        metricsLabel.text = PerformanceMetricsMonitor.shared.snapshot.displayLine
    }

    @objc private func sourceChanged() {
        let new = TimeSource.allCases[sourceControl.selectedSegmentIndex]
        statusLabel.text = "正在校时 \(new.rawValue) …"
        StopwatchEngine.shared.setSource(new) { [weak self] ok in
            self?.statusLabel.text = ok ? "已同步 \(new.rawValue) 时间" : "\(new.rawValue) 校时失败"
            Task { @MainActor in
                LiveActivityController.shared.refreshIfEnabled()
            }
        }
    }

    @objc private func syncTapped() {
        statusLabel.text = "正在重新校时…"
        StopwatchEngine.shared.resync { [weak self] ok in
            self?.statusLabel.text = ok ? "重新同步成功" : "校时失败"
            Task { @MainActor in
                LiveActivityController.shared.refreshIfEnabled()
            }
        }
    }

    @objc private func dynamicIslandSwitchChanged() {
        LiveActivityController.shared.setEnabled(dynamicIslandSwitch.isOn)
        dynamicIslandSwitch.isOn = LiveActivityController.shared.isEnabled
    }

    @objc private func startTapped() {
        pipRenderer.startPiP()
        statusLabel.text = "悬浮窗已启动，切到其他 App 试试"
    }

    private static func makeDisplayText(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .foregroundColor: UIColor(red: 0.2, green: 1.0, blue: 0.6, alpha: 1)
            ]
        )
        if !text.isEmpty {
            result.addAttribute(
                .foregroundColor,
                value: UIColor(red: 1.0, green: 0.25, blue: 0.18, alpha: 1),
                range: NSRange(location: text.count - 1, length: 1)
            )
        }
        return result
    }
}
