//
//  Modified MIT License
//
//  Copyright (c) 2010-2018 Kite Tech Ltd. https://www.kite.ly
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The software MAY ONLY be used with the Kite Tech Ltd platform and MAY NOT be modified
//  to be used with any competitor platforms. This means the software MAY NOT be modified
//  to place orders with any competitors to Kite Tech Ltd, all orders MUST go through the
//  Kite Tech Ltd platform servers.
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import UIKit

protocol PageSetupDelegate: class {
    func didFinishEditingPage(_ index: Int?, pageType: PageType?, productLayout: ProductLayout?, color: ProductColor?, editor: PageSetupViewController)
}

extension PageSetupDelegate {
    func didFinishEditingPage(_ index: Int? = nil, pageType: PageType? = nil, productLayout: ProductLayout? = nil, color: ProductColor? = nil, editor: PageSetupViewController) {
        didFinishEditingPage(index, pageType: pageType, productLayout: productLayout, color: color, editor: editor)
    }
}

enum PageType {
    case cover, first, last, left, right
}

class PageSetupViewController: UIViewController, PhotobookNavigationBarDelegate {

    private struct Constants {
        static let photobookSideMargin: CGFloat = 20.0
    }
    
    private enum Tool: Int {
        case selectLayout, selectAsset, selectColor, placeAsset, editText
    }
    
    @IBOutlet private weak var photobookContainerView: UIView!
    @IBOutlet private weak var assetSelectionContainerView: UIView!
    @IBOutlet private weak var layoutSelectionContainerView: UIView!
    @IBOutlet private weak var placementContainerView: UIView!
    @IBOutlet private weak var colorSelectionContainerView: UIView!
    @IBOutlet private weak var textEditingContainerView: UIView!
    
    @IBOutlet private var toolbarButtons: [UIButton]!
    @IBOutlet private weak var toolbar: UIToolbar! {
        didSet { toolbar.clipsToBounds = true }
    }
    @IBOutlet private var cancelBarButtonItem: UIBarButtonItem!
    
    var photobookNavigationBarType: PhotobookNavigationBarType = .clear
    var previewAssetImage: UIImage?
    weak var photobookDelegate: PhotobookDelegate?
    
    private var assetSelectorViewController: AssetSelectorViewController!
    private var layoutSelectionViewController: LayoutSelectionViewController!
    private var assetPlacementViewController: AssetPlacementViewController!
    private var colorSelectionViewController: ColorSelectionViewController!
    private var textEditingViewController: TextEditingViewController!
    
    private var enteredEditingDate = Date()
    private var appBackgroundedDate: Date?
    private var secondsSpentInBackground: TimeInterval = 0
    
    @IBOutlet private weak var coverFrameView: CoverFrameView! {
        didSet {
            coverFrameView.isHidden = pageType != .cover
        }
    }
    @IBOutlet private weak var photobookFrameView: PhotobookFrameView! {
        didSet {
            photobookFrameView.isHidden = pageType == .cover
        }
    }
    
    @IBOutlet private weak var photobookHorizontalAlignmentConstraint: NSLayoutConstraint!
    
    @IBOutlet private weak var coverAssetContainerView: UIView!
    @IBOutlet private weak var coverAssetImageView: UIImageView!
    @IBOutlet private weak var leftAssetContainerView: UIView!
    @IBOutlet private weak var leftAssetImageView: UIImageView!
    @IBOutlet private weak var rightAssetContainerView: UIView!
    @IBOutlet private weak var rightAssetImageView: UIImageView!
    
    private weak var assetContainerView: UIView! {
        switch pageType {
        case .left?, .last?:
            return leftAssetContainerView
        case .right?, .first?:
            return rightAssetContainerView
        case .cover?:
            return coverAssetContainerView
        default:
            return nil
        }
    }

    private weak var assetImageView: UIImageView! {
        switch pageType {
        case .left?, .last?:
            return leftAssetImageView
        case .right?, .first?:
            return rightAssetImageView
        case .cover?:
            return coverAssetImageView
        default:
            return nil
        }
    }
    
    // Public settings
    weak var delegate: PageSetupDelegate?
    weak var assetsDelegate: PhotobookAssetsDelegate?
    
    var assets: [Asset]! {
        return assetsDelegate!.assets!
    }
    
    var pageIndex: Int! {
        didSet {
            guard pageIndex != nil else {
                fatalError("Page editing started without a layout index")
            }
            
            productLayout = product.productLayouts[pageIndex].shallowCopy()

            pageType = product.pageType(forLayoutIndex: pageIndex)
            
            if pageType == .cover {
                selectedColor = product.coverColor
                availableLayouts = ProductManager.shared.currentProduct!.coverLayouts
            } else {
                selectedColor = product.pageColor
                availableLayouts = ProductManager.shared.currentProduct!.layouts
            }
        }
    }
    
    private var productLayout: ProductLayout!
    private var availableLayouts: [Layout]!
    private var pageSize: CGSize = .zero
    private var hasDoneSetup = false
    private var pageType: PageType!
    private var isDoublePage: Bool {
        return productLayout.layout.isDoubleLayout
    }
    
    private var pageView: PhotobookPageView! {
        switch pageType {
        case .left?, .last?:
            return photobookFrameView.leftPageView
        case .right?, .first?:
            return photobookFrameView.rightPageView
        case .cover?:
            return coverFrameView.pageView
        default:
            return nil
        }
    }
    private var oppositePageView: PhotobookPageView? {
        switch pageType {
        case .left?:
            return photobookFrameView.rightPageView
        case .right?:
            return photobookFrameView.leftPageView
        default:
            return nil
        }
    }
    
    private var selectedColor: ProductColor!
    private lazy var pageColor = product.pageColor
    
    private var previouslySelectedButton: UIButton!
    
    private var product: PhotobookProduct! {
        return ProductManager.shared.currentProduct
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        toolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
        toolbarButtons[Tool.selectLayout.rawValue].isSelected = true
        sendScreenViewedAnalyticsEvent(for: Tool.selectLayout)
        
        NotificationCenter.default.addObserver(self, selector: #selector(albumsWereUpdated(_:)), name: AssetsNotificationName.albumsWereUpdated, object: nil)
        
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: OperationQueue.main, using: { [weak welf = self] _ in            
            guard let appBackgroundedDate = welf?.appBackgroundedDate else { return }
            welf?.secondsSpentInBackground += Date().timeIntervalSince(appBackgroundedDate)
        })
        
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: OperationQueue.main, using: { [weak welf = self] _ in
            welf?.appBackgroundedDate = Date()
        })
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if !hasDoneSetup {
            (navigationController?.navigationBar as? PhotobookNavigationBar)?.setBarType(photobookNavigationBarType)
            
            pageView.shouldSetImage = false
            
            coverFrameView.color = product.coverColor
            coverFrameView.pageView.aspectRatio = product.photobookTemplate.coverAspectRatio
            coverFrameView.pageView.interaction = .assetAndText
            coverFrameView.pageView.delegate = self
            
            photobookFrameView.pageColor = product.pageColor
            photobookFrameView.coverColor = product.coverColor

            setupPhotobookPages()
            
            photobookFrameView.leftPageView.interaction = .assetAndText
            photobookFrameView.rightPageView.interaction = .assetAndText
            
            photobookFrameView.leftPageView.delegate = self
            photobookFrameView.rightPageView.delegate = self
            
            setupPhotobookFrame()
            setupAssetPlacement()
            setupAssetSelection()
            setupLayoutSelection()
            setupColorSelection()
            setupTextEditing()
            
            pageView.pageIndex = pageIndex
            pageView.productLayout = productLayout
            pageView.setupTextBox(mode: .userTextOnly)
            
            // Setup the opposite layout if necessary
            if !isDoublePage && (pageType == .left || pageType == .right) {
                let oppositeIndex = pageIndex! + (pageType == .left ? 1 : -1)
                oppositePageView!.shouldSetImage = false
                oppositePageView!.pageIndex = oppositeIndex
                oppositePageView!.productLayout = product.productLayouts[oppositeIndex]
                oppositeProductLayout = product.productLayouts[oppositeIndex]
                oppositePageView!.setupTextBox(mode: .userTextOnly)
            }
            hideViewsBeforeAnimation()
            
            hasDoneSetup = true
        }
    }
    
    private func hideViewsBeforeAnimation() {
        storyboardBackgroundColor = view.backgroundColor
        view.backgroundColor = .clear
        
        assetSelectionContainerView.alpha = 0.0
        photobookContainerView.alpha = 0.0
        toolbar.alpha = 0.0
    }

    private lazy var animatableAssetImageView = UIImageView()
    private var containerRect: CGRect!
    private var storyboardBackgroundColor: UIColor!
    private var frameView: UIView {
        return pageType == .cover ? coverFrameView : photobookFrameView
    }
    private var oppositeProductLayout: ProductLayout?
    
    func animateFromPhotobook(frame: CGRect, completion: @escaping (() -> Void)) {
        containerRect = frame
        
        // Use preview image for the animation and editing until a higher resolution image is available
        let previewAssetImage = productLayout?.productLayoutAsset?.currentImage
        pageView.shouldSetImage = true
        pageView.setupImageBox(with: previewAssetImage)
        
        // Use preview image for the opposite page if needed
        if let oppositePageView = oppositePageView, let oppositeProductLayout = oppositeProductLayout {
            let oppositeAssetImage = oppositeProductLayout.productLayoutAsset?.currentImage
            oppositePageView.shouldSetImage = true
            oppositePageView.setupImageBox(with: oppositeAssetImage)
        }

        animatableAssetImageView.transform = .identity
        animatableAssetImageView.frame = frameView.bounds
        animatableAssetImageView.center = CGPoint(x: containerRect.midX, y: containerRect.midY)
        animatableAssetImageView.image = frameView.snapshot()
        
        let initialScale = containerRect.width / frameView.bounds.width
        animatableAssetImageView.transform = CGAffineTransform.identity.scaledBy(x: initialScale, y: initialScale)

        view.addSubview(animatableAssetImageView)
        
        pageView.setupTextBox(mode: .placeHolder)
        
        let shouldShowAssetSelection = self.productLayout.layout.imageLayoutBox != nil && self.productLayout.productLayoutAsset?.asset == nil        
        if shouldShowAssetSelection {
            toolbarButtons[Tool.selectLayout.rawValue].isSelected = false
            toolbarButtons[Tool.selectAsset.rawValue].isSelected = true
        }
        
        UIView.animate(withDuration: 0.1) {
            self.view.backgroundColor = self.storyboardBackgroundColor
        }
        
        UIView.animate(withDuration: 0.3, delay: 0.1, options: [], animations: {
            if shouldShowAssetSelection {
                self.assetSelectionContainerView.alpha = 1.0
            } else {
                self.layoutSelectionContainerView.alpha = 1.0
            }
            self.toolbar.alpha = 1.0
            
            (self.navigationController?.navigationBar as? PhotobookNavigationBar)?.setBarType(.clear)
        }, completion: nil)
        
        UIView.animateKeyframes(withDuration: 0.3, delay: 0.0, options: [ .calculationModeCubicPaced ], animations: {
            UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 1.0) {
                self.animatableAssetImageView.frame = self.frameView.frame
            }
        }, completion: { _ in
            self.photobookContainerView.alpha = 1.0
            self.animatableAssetImageView.alpha = 0.0
            
            // Request higher resolution image
            self.pageView.setupImageBox(with: nil, animated: false, loadThumbnailFirst: false)

            completion()
        })
    }
    
    func animateBackToPhotobook(_ completion: @escaping (() -> Void)) {
        animatableAssetImageView.transform = .identity
        animatableAssetImageView.frame = frameView.frame
        animatableAssetImageView.image = frameView.snapshot()
        
        animatableAssetImageView.alpha = 1.0
        frameView.alpha = 0.0
        
        UIView.animate(withDuration: 0.1, animations: {
            self.assetSelectionContainerView.alpha = 0.0
            self.layoutSelectionContainerView.alpha = 0.0
            self.colorSelectionContainerView.alpha = 0.0
            self.toolbar.alpha = 0.0
            if let navigationController = self.navigationController {
                navigationController.navigationBar.alpha = 0.0
            }
        })

        UIView.animateKeyframes(withDuration: 0.3, delay: 0.0, options: [ .calculationModeCubicPaced ], animations: {
            UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 1.0) {
                self.animatableAssetImageView.frame = self.containerRect
            }
        }, completion: { _ in
            UIView.animate(withDuration: 0.3, animations: {
                self.animatableAssetImageView.alpha = 0.0
            })
            UIView.animate(withDuration: 0.2, animations: {
                self.view.backgroundColor = .clear
            }, completion: { _ in
                completion()
            })
        })
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func albumsWereUpdated(_ notification: Notification) {
        guard let albumsChanges = notification.object as? [AlbumChange] else { return }
        
        var removedAssets = [Asset]()
        for albumChange in albumsChanges {
            if let assetsRemoved = PhotobookAsset.assets(from: albumChange.assetsRemoved) {
                removedAssets.append(contentsOf: assetsRemoved)
            }
        }
        
        for removedAsset in removedAssets {
            if removedAsset.identifier == productLayout.asset?.identifier {
                productLayout.asset = nil
                updateAll(with: nil)
                assetSelectorViewController.selectedAsset = nil
                break
            }
        }
    }

    private func transitionPhotobookFrame() {
        UIView.animate(withDuration: 0.1, animations: {
            self.photobookFrameView.layer.shadowOpacity = 0.0
            self.photobookFrameView.leftPageView.alpha = 0.0
            self.photobookFrameView.rightPageView.alpha = 0.0
        }) { _ in
            self.setupPhotobookPages()
            self.photobookFrameView.resetPageColor()
            
            UIView.animate(withDuration: 0.3, animations: {
                self.setupPhotobookFrame()

                self.pageView.setupLayoutBoxes(animated: false)
                self.photobookContainerView.layoutIfNeeded()
            }) { _ in
                UIView.animate(withDuration: 0.1) {
                    self.photobookFrameView.layer.shadowOpacity = 1.0
                    self.photobookFrameView.leftPageView.alpha = 1.0
                    self.photobookFrameView.rightPageView.alpha = 1.0
                }
            }
        }
    }
    
    private func setupPhotobookPages() {
        let aspectRatio = pageType == .cover ? product.photobookTemplate.coverAspectRatio : product.photobookTemplate.pageAspectRatio
        
        if isDoublePage {
            photobookFrameView.leftPageView.aspectRatio = pageType == .left ? aspectRatio * 2.0 : 0.0
            photobookFrameView.rightPageView.aspectRatio = pageType == .left ? 0.0 : aspectRatio * 2.0
            return
        }
        photobookFrameView.leftPageView.aspectRatio = aspectRatio
        photobookFrameView.rightPageView.aspectRatio = aspectRatio
    }
    
    private func setupPhotobookFrame() {
        photobookFrameView.width = (view.bounds.width - 2.0 * Constants.photobookSideMargin) * 2.0
        photobookFrameView.transform = isDoublePage ? CGAffineTransform.identity.scaledBy(x: 0.5, y: 0.5) : .identity

        switch pageType! {
        case .last:
            photobookFrameView.isRightPageVisible = false
            fallthrough
        case .left:
            photobookHorizontalAlignmentConstraint.constant = view.bounds.width - Constants.photobookSideMargin
        case .first:
            photobookFrameView.isLeftPageVisible = false
            fallthrough
        case .right:
            photobookHorizontalAlignmentConstraint.constant = Constants.photobookSideMargin
        case .cover:
            break
        }
        photobookFrameView.layoutIfNeeded()
        
        let bleed = product.bleed(forPageSize: pageView.bounds.size, type: pageType)
        photobookFrameView.leftPageView.bleed = bleed
        photobookFrameView.rightPageView.bleed = bleed
        
        if isDoublePage {
            photobookHorizontalAlignmentConstraint.constant = view.bounds.width * 0.5
        }
    }
    
    private func setupAssetSelection() {
        assetSelectorViewController.photobookDelegate = photobookDelegate
        assetSelectorViewController.assetsDelegate = assetsDelegate
        assetSelectorViewController.selectedAsset = productLayout.asset
    }
    
    private func setupLayoutSelection() {
        layoutSelectionViewController.pageIndex = pageIndex
        layoutSelectionViewController.pageType = pageType
        layoutSelectionViewController.asset = productLayout.asset
        if pageType == .first || pageType == .last {
            layoutSelectionViewController.layouts = availableLayouts.filter { !$0.isDoubleLayout }
        } else {
            layoutSelectionViewController.layouts = availableLayouts
        }
        layoutSelectionViewController.selectedLayout = productLayout!.layout
        layoutSelectionViewController.coverColor = product.coverColor
        layoutSelectionViewController.pageColor = product.pageColor
        layoutSelectionViewController.isEditingDoubleLayout = productLayout!.layout.isDoubleLayout
    }
    
    private func setupColorSelection() {
        colorSelectionViewController.selectedColor = selectedColor
    }
    
    private func setupTextEditing() {
        let enabled = productLayout.layout.textLayoutBox != nil
        toolbarButtons[Tool.editText.rawValue].isEnabled = enabled
    }
    
    private func updateAll(with asset: Asset?) {
        layoutSelectionViewController.asset = asset
        productLayout.asset = asset
        
        // If the current layout does not have an image box, find the first layout that does and use it
        if productLayout.layout.imageLayoutBox == nil {
            let defaultLayout = availableLayouts.first(where: { $0.imageLayoutBox != nil })
            
            productLayout.layout = defaultLayout
            pageView.setupTextBox()
            
            layoutSelectionViewController.selectedLayout = productLayout.layout
        }
        pageView.setupImageBox(with: nil, animated: false, loadThumbnailFirst: false)
        setupAssetPlacement()
    }
    
    private func secondsSinceEditingEntered() -> Int {
        return Int(Date().timeIntervalSince(enteredEditingDate))
    }
    
    // MARK: - Navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let identifier = segue.identifier else { return }
        switch identifier {
        case "AssetSelectionSegue":
            assetSelectorViewController = segue.destination as? AssetSelectorViewController
            assetSelectorViewController.delegate = self
        case "LayoutSelectionSegue":
            layoutSelectionViewController = segue.destination as? LayoutSelectionViewController
            layoutSelectionViewController.delegate = self
        case "PlacementSegue":
            assetPlacementViewController = segue.destination as? AssetPlacementViewController
        case "ColorSelectionSegue":
            colorSelectionViewController = segue.destination as? ColorSelectionViewController
            colorSelectionViewController.delegate = self
        case "TextEditingSegue":
            textEditingViewController = segue.destination as? TextEditingViewController
            textEditingViewController.delegate = self
        default:
            break
        }
    }
    
    private func setupAssetPlacement() {
        let enabled = productLayout.layout.imageLayoutBox != nil && productLayout.asset != nil
        toolbarButtons[Tool.placeAsset.rawValue].isEnabled = enabled
    }
    
    @IBAction func tappedCancelButton(_ sender: UIBarButtonItem) {
        Analytics.shared.trackAction(.editingCancelled, [Analytics.PropertyNames.secondsInEditing: secondsSinceEditingEntered() - Int(secondsSpentInBackground)
            ])
        
        delegate?.didFinishEditingPage(editor: self)
    }
    
    @IBAction func tappedDoneButton(_ sender: UIBarButtonItem) {
        // If in the asset placement tool, go back to the previous tool
        if toolbarButtons[Tool.placeAsset.rawValue].isSelected {
            // Check if the previous tool is the text editor. If so, select the first tool instead
            let previousTool = Tool(rawValue: toolbarButtons.firstIndex(of: previouslySelectedButton)!)
            if previousTool == .editText {
                previouslySelectedButton = toolbarButtons.first!
            }
            tappedToolButton(previouslySelectedButton)
            return
        }
        
        if productLayout.layout.imageLayoutBox == nil {
            // Remove the asset if the layout doesn't have an image box
            productLayout.asset = nil
        }
        // Work out whether we need to cut the user's text to fit the layout
        let visibleText = textEditingViewController.visibleTextInLayout()
        if productLayout.layout.textLayoutBox != nil &&
            productLayout.productLayoutText?.text != nil &&
            visibleText != nil &&
            visibleText != productLayout.productLayoutText?.text
        {
            productLayout.productLayoutText!.text = visibleText
        }
        
        Analytics.shared.trackAction(.editingConfirmed, [Analytics.PropertyNames.secondsInEditing: secondsSinceEditingEntered() - Int(secondsSpentInBackground)])
        
        delegate?.didFinishEditingPage(pageIndex, pageType: pageType, productLayout: productLayout, color: selectedColor, editor: self)
    }
    
    private var isAnimatingTool = false
    @IBAction func tappedToolButton(_ sender: UIButton) {

        guard !isAnimatingTool, let index = toolbarButtons.firstIndex(of: sender),
            !toolbarButtons[index].isSelected,
            let tool = Tool(rawValue: index) else { return }
        
        sendScreenViewedAnalyticsEvent(for: tool)

        // Store currently selected tool so we may come back to it
        previouslySelectedButton = toolbarButtons.first { $0.isSelected }
        
        let placeAssetWasSelected = toolbarButtons[Tool.placeAsset.rawValue].isSelected
        let textEditingWasSelected = toolbarButtons[Tool.editText.rawValue].isSelected
        
        for button in toolbarButtons { button.isSelected = (button === sender) }
        
        isAnimatingTool = true
        
        assetPlacementViewController.accessibilityElementsHidden = true
        textEditingViewController.accessibilityElementsHidden = true
        assetSelectionContainerView.accessibilityElementsHidden = true
        layoutSelectionContainerView.accessibilityElementsHidden = true
        colorSelectionContainerView.accessibilityElementsHidden = true
        photobookContainerView.accessibilityElementsHidden = true

        switch tool {
        case .selectAsset, .selectLayout, .selectColor:
            if placeAssetWasSelected {
                assetPlacementViewController.animateBackToPhotobook { image in
                    self.assetImageView.image = image
                    self.assetImageView.transform = self.productLayout!.productLayoutAsset!.transform
                    self.view.sendSubviewToBack(self.placementContainerView)
                    self.isAnimatingTool = false
                }
            } else if textEditingWasSelected {
                textEditingViewController.animateOff {
                    self.view.sendSubviewToBack(self.textEditingContainerView)
                    self.isAnimatingTool = false
                }
            } else {
                isAnimatingTool = false
            }

            assetSelectionContainerView.accessibilityElementsHidden = false
            layoutSelectionContainerView.accessibilityElementsHidden = false
            colorSelectionContainerView.accessibilityElementsHidden = false
            photobookContainerView.accessibilityElementsHidden = false
            
            UIView.animate(withDuration: 0.1, animations: {
                self.photobookContainerView.alpha = 1.0
                self.assetSelectionContainerView.alpha = tool.rawValue == Tool.selectAsset.rawValue ? 1.0 : 0.0
                self.layoutSelectionContainerView.alpha = tool.rawValue == Tool.selectLayout.rawValue ? 1.0 : 0.0
                self.colorSelectionContainerView.alpha = tool.rawValue == Tool.selectColor.rawValue ? 1.0 : 0.0
            })
            
            setCancelButton(hidden: false)
        case .placeAsset:
            let containerRect = placementContainerView.convert(assetContainerView.frame, from: pageView)
            assetPlacementViewController.productLayout = productLayout
            assetPlacementViewController.initialContainerRect = containerRect
            assetPlacementViewController.previewAssetImage = assetImageView.image
            assetPlacementViewController.pageType = pageType
            assetPlacementViewController.accessibilityElementsHidden = false

            if textEditingWasSelected {
                textEditingViewController.animateOff {
                    self.view.sendSubviewToBack(self.textEditingContainerView)
                    self.isAnimatingTool = false
                }
            } else {
                view.bringSubviewToFront(placementContainerView)
                assetPlacementViewController.animateFromPhotobook() {
                    self.isAnimatingTool = false
                }
            }
            setCancelButton(hidden: true)
        case .editText:
            view.bringSubviewToFront(textEditingContainerView)
            self.textEditingContainerView.alpha = 1.0
            
            textEditingViewController.accessibilityElementsHidden = false
            
            textEditingViewController.productLayout = productLayout!
            textEditingViewController.assetImage = assetImageView.image
            textEditingViewController.pageColor = selectedColor
            textEditingViewController.pageType = pageType
            if placeAssetWasSelected {
                let containerRect = textEditingContainerView.convert(assetPlacementViewController.targetRect!, from: placementContainerView)
                textEditingViewController.initialContainerRect = containerRect
            } else {
                textEditingViewController.initialContainerRect = textEditingContainerView.convert(assetContainerView.frame, from: pageView)
            }
            textEditingViewController.animateOn {
                self.isAnimatingTool = false
            }
        }
        
        setTopBars(hidden: tool == .editText)
    }
    
    private func setTopBars(hidden: Bool) {
        navigationController?.setNavigationBarHidden(hidden, animated: true)
        setNeedsStatusBarAppearanceUpdate()
    }
    
    private func setCancelButton(hidden: Bool) {
        navigationItem.setLeftBarButton(hidden ? nil : cancelBarButtonItem, animated: true)
    }
    
    override var prefersStatusBarHidden: Bool {
        return toolbarButtons != nil ? toolbarButtons[Tool.editText.rawValue].isSelected : false
    }
    
    private func sendScreenViewedAnalyticsEvent(for tool: Tool) {
        let screenName: Analytics.ScreenName
        switch tool {
        case .selectAsset:
            screenName = .pageEditingPhotoSelection
        case .selectLayout:
            screenName = .layoutSelection
        case .selectColor:
            screenName = .colorSelection
        case .placeAsset:
            screenName = .photoPlacement
        case .editText:
            screenName = .textEditing
        }
        
        Analytics.shared.trackScreenViewed(screenName)
    }
}

extension PageSetupViewController: LayoutSelectionDelegate {
    
    func didSelectLayout(_ layout: Layout) {
        let shouldTransitionPhotobookFrame = layout.isDoubleLayout != productLayout.layout.isDoubleLayout
        
        productLayout.layout = layout
        
        if shouldTransitionPhotobookFrame {
            transitionPhotobookFrame()
        } else {
            pageView.setupImageBox(with: nil, animated: false, loadThumbnailFirst: false)
            pageView.setupTextBox()
        }
        
        // Deselect the asset if the layout does not have an image box
        if productLayout.layout.imageLayoutBox == nil {
            assetSelectorViewController.selectedAsset = nil
        } else if productLayout.asset != nil && assetSelectorViewController.selectedAsset == nil {
            assetSelectorViewController.reselectAsset(productLayout.asset!)
        }
        
        setupAssetPlacement()
        setupTextEditing()
    }
}

extension PageSetupViewController: AssetSelectorDelegate {
    
    func didSelect(asset: Asset) {
        updateAll(with: asset)
    }
}

extension PageSetupViewController: ColorSelectorDelegate {
    
    func didSelect(_ color: ProductColor) {
        selectedColor = color
        
        if pageType == .cover {
            coverFrameView.color = color
            coverFrameView.resetCoverColor()
            
            layoutSelectionViewController.coverColor = color
        } else {
            photobookFrameView.pageColor = color
            photobookFrameView.resetPageColor()
            
            layoutSelectionViewController.pageColor = color
        }
        
    }
}

extension PageSetupViewController: TextEditingDelegate {
    
    func didChangeText() {
        pageView.setupTextBox()
        tappedToolButton(previouslySelectedButton)
    }
    
    func didChangeFontType() {
        pageView.setupTextBox()
    }
    
    func shouldReactToKeyboardAppearance() -> Bool {
        return toolbarButtons[Tool.editText.rawValue].isSelected
    }
}

extension PageSetupViewController: PhotobookPageViewDelegate {
    
    func didTapOnAsset(at index: Int) {
        guard assetImageView.image != nil else {
            // If there is no photo, switch to the photo selection tool
            tappedToolButton(toolbarButtons[Tool.selectAsset.rawValue])
            return
        }
        // Otherwise switch to the photo placement tool
        tappedToolButton(toolbarButtons[Tool.placeAsset.rawValue])
    }

    func didTapOnText(at index: Int) {
        tappedToolButton(toolbarButtons[Tool.editText.rawValue])
    }
}
