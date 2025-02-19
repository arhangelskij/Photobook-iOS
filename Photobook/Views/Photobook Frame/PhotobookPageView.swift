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

@objc protocol PhotobookPageViewDelegate: class {
    @objc optional func didTapOnPage(_ page: PhotobookPageView, at index: Int)
    @objc optional func didTapOnAsset(at index: Int)
    @objc optional func didTapOnText(at index: Int)
}

enum PhotobookPageViewInteraction {
    case disabled // The user cannot tap on the page
    case wholePage // The user can tap anywhere on the page for a single action
    case assetAndText // The user can tap on the page and the text for two different actions
}

enum TextBoxMode {
    case placeHolder // Shows a placeholder "Add your own text" or the user's input if available
    case userTextOnly // Only shows the user's input if available. Blank otherwise.
    case linesPlaceholder // Shows a graphical representation of text in the form of two lines
}

class PhotobookPageView: UIView {
    
    weak var delegate: PhotobookPageViewDelegate?
    var pageIndex: Int?
    var aspectRatio: CGFloat? {
        didSet {
            guard let aspectRatio = aspectRatio else { return }
            let priority = self.aspectRatioConstraint.priority
            self.removeConstraint(self.aspectRatioConstraint)
            aspectRatioConstraint = NSLayoutConstraint(item: self, attribute: .width, relatedBy: .equal, toItem: self, attribute: .height, multiplier: aspectRatio, constant: 0)
            aspectRatioConstraint.priority = priority
            self.addConstraint(aspectRatioConstraint)
        }
    }
    var isVisible: Bool = false {
        didSet {
            for subview in subviews {
                subview.isHidden = !isVisible
            }
        }
    }
    var color: ProductColor = .white
    
    private var hasSetupGestures = false
    var productLayout: ProductLayout?
    
    var interaction: PhotobookPageViewInteraction = .disabled {
        didSet {
            if oldValue != interaction {
                hasSetupGestures = false
                setupGestures()
            }
        }
    }
    var bleed: CGFloat?
    
    private var isShowingTextPlaceholder = false
    
    @IBOutlet private weak var bleedAssetContainerView: UIView! // Hierarchical order: assetContainerView, bleedingAssetContainerView & assetImageView
    @IBOutlet private weak var assetContainerView: UIView!
    @IBOutlet private weak var assetPlaceholderIconImageView: UIImageView!
    @IBOutlet private weak var assetImageView: UIImageView!
    @IBOutlet private weak var textAreaView: UIView?
    @IBOutlet private weak var pageTextLabel: UILabel? {
        didSet {
            pageTextLabel!.alpha = 0.0
            pageTextLabel!.layer.anchorPoint = CGPoint(x: 0.0, y: 0.0)
        }
    }
    @IBOutlet private weak var textLabelPlaceholderBoxView: TextLabelPlaceholderBoxView? {
        didSet { textLabelPlaceholderBoxView!.alpha = 0.0 }
    }
    
    @IBOutlet private var aspectRatioConstraint: NSLayoutConstraint!
    
    private var product: PhotobookProduct! {
        return ProductManager.shared.currentProduct
    }
    
    override func layoutSubviews() {
        setupImageBox(with: productLayout?.productLayoutAsset?.currentImage)
        adjustTextLabel()
        setupGestures()
    }
    
    private func setupGestures() {
        guard !hasSetupGestures else { return }
        
        if let gestureRecognizers = gestureRecognizers {
            for gestureRecognizer in gestureRecognizers {
                removeGestureRecognizer(gestureRecognizer)
            }
        }
        
        switch interaction {
        case .wholePage:
            let pageTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapOnPage(_:)))
            addGestureRecognizer(pageTapGestureRecognizer)
        case .assetAndText:
            let assetTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapOnAsset(_:)))
            assetContainerView.addGestureRecognizer(assetTapGestureRecognizer)
            
            let textTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapOnText(_:)))
            textAreaView?.addGestureRecognizer(textTapGestureRecognizer)
        default:
            break
        }
        hasSetupGestures = true
    }
    
    func setupLayoutBoxes(animated: Bool = true) {
        guard assetImageView.image == nil && productLayout?.layout.imageLayoutBox != nil && animated else {
            setupImageBox(animated: false)
            setupTextBox()
            return
        }
        
        assetImageView.alpha = 0.0
        setupImageBox()
        setupTextBox()
    }
    
    private var containerView: UIView! {
        return bleedAssetContainerView != nil ? bleedAssetContainerView! : assetContainerView!
    }
    
    func setupImageBox(with assetImage: UIImage? = nil, animated: Bool = true, loadThumbnailFirst: Bool = true) {
        
        // Avoid recalculating transforms with intermediate heights, e.g. when UICollectionViewCells are still determining their height
        let finalBounds = bounds.width > 0 && (aspectRatio ?? 0.0) > 0.0 ? CGSize(width: bounds.width, height: bounds.width / aspectRatio!) : bounds.size
        guard let imageBox = productLayout?.layout.imageLayoutBox,
                finalBounds.width > 0.0 && finalBounds.height > 0.0 else {
            assetContainerView.alpha = 0.0
            return
        }

        assetContainerView.alpha = 1.0
        assetContainerView.frame = imageBox.rectContained(in: finalBounds)
        if bleedAssetContainerView != nil {
            bleedAssetContainerView.frame = imageBox.bleedRect(in: assetContainerView.bounds.size, withBleed: bleed)
        }
        setImagePlaceholder()
        
        guard let index = pageIndex, let asset = productLayout?.asset else {
            assetImageView.image = nil
            return
        }

        if let assetImage = assetImage {
            setImage(image: assetImage)
            return
        }
        
        var size = assetContainerView.bounds.size
        if productLayout!.hasBeenEdited { size = 3.0 * size }
        
        AssetLoadingManager.shared.image(for: asset, size: size, loadThumbnailFirst: loadThumbnailFirst, progressHandler: nil, completionHandler: { [weak welf = self] (image, _) in
            guard welf?.pageIndex == index, let image = image, let productLayoutAsset = welf?.productLayout?.productLayoutAsset else { return }
            
            if productLayoutAsset.currentImage == nil || (asset.identifier == productLayoutAsset.currentIdentifier && productLayoutAsset.currentImage!.size.width <= image.size.width) {
                productLayoutAsset.currentImage = image
            }
            productLayoutAsset.currentIdentifier = asset.identifier
            
            welf?.setImage(image: productLayoutAsset.currentImage!)
            
            UIView.animate(withDuration: animated ? 0.1 : 0.0) {
                welf?.assetImageView.alpha = 1.0
            }
        })
    }
    
    var shouldSetImage: Bool = false
    
    func clearImage() {
        assetImageView.image = nil
    }
    
    private func setImage(image: UIImage) {
        guard let productLayoutAsset = productLayout?.productLayoutAsset,
              let asset = productLayoutAsset.asset,
              shouldSetImage
            else { return }
        
        assetImageView.transform = .identity
        assetImageView.frame = CGRect(x: 0.0, y: 0.0, width: asset.size.width, height: asset.size.height)
        assetImageView.image = image
        assetImageView.center = CGPoint(x: containerView.bounds.midX, y: containerView.bounds.midY)
        
        productLayoutAsset.containerSize = containerView.bounds.size
        assetImageView.transform = productLayoutAsset.transform
    }
    
    func setupTextBox(mode: TextBoxMode = .placeHolder) {
        guard let textBox = productLayout?.layout.textLayoutBox else {
            if let placeholderView = textLabelPlaceholderBoxView { placeholderView.alpha = 0.0 }
            if let pageTextLabel = pageTextLabel { pageTextLabel.alpha = 0.0 }
            return
        }
        
        if mode == .linesPlaceholder, let placeholderView = textLabelPlaceholderBoxView {
            placeholderView.alpha = 1.0
            placeholderView.frame = textBox.rectContained(in: bounds.size)
            placeholderView.color = color
            placeholderView.setNeedsDisplay()
            return
        }

        guard let pageTextLabel = pageTextLabel else { return }
        pageTextLabel.alpha = 1.0
        
        if (productLayout?.text ?? "").isEmpty && mode == .placeHolder {
            pageTextLabel.text = NSLocalizedString("Views/Photobook Frame/PhotobookPageView/pageTextLabel/placeholder",
                                     value: "Add your own text",
                                     comment: "Placeholder text to show on a cover / page")
            isShowingTextPlaceholder = true
        } else {
            pageTextLabel.text = productLayout?.text
            isShowingTextPlaceholder = false
        }

        adjustTextLabel()
        setTextColor()
    }
    
    private func adjustTextLabel() {
        guard let pageTextLabel = pageTextLabel, let textBox = productLayout?.layout.textLayoutBox else { return }
        
        let finalFrame = textBox.rectContained(in: bounds.size)
        
        let originalSize = pageIndex == 0 ? product.photobookTemplate.coverSize : product.photobookTemplate.pageSize
        
        pageTextLabel.transform = .identity
        pageTextLabel.frame = CGRect(x: finalFrame.minX, y: finalFrame.minY, width: originalSize.width * textBox.rect.width, height: originalSize.height * textBox.rect.height)
        
        textAreaView?.frame = finalFrame
        
        let scale = finalFrame.width / (originalSize.width * textBox.rect.width)
        guard pageTextLabel.text != nil else {
            pageTextLabel.transform = pageTextLabel.transform.scaledBy(x: scale, y: scale)            
            return
        }
        
        let fontType = isShowingTextPlaceholder ? .plain : (productLayout!.fontType ?? .plain)
        var fontSize = fontType.sizeForScreenToPageRatio()
        if isShowingTextPlaceholder { fontSize *= 2.0 } // Make text larger so the placeholder can be read
        
        pageTextLabel.attributedText = fontType.attributedText(with: pageTextLabel.text!, fontSize: fontSize, fontColor: color.fontColor())
        
        let textHeight = pageTextLabel.attributedText!.height(for: pageTextLabel.bounds.width)
        if textHeight < pageTextLabel.bounds.height { pageTextLabel.frame.size.height = ceil(textHeight) }
        
        pageTextLabel.transform = pageTextLabel.transform.scaledBy(x: scale, y: scale)
    }
        
    private func setImagePlaceholder() {
        let iconSize = min(assetContainerView.bounds.width, assetContainerView.bounds.height)

        assetContainerView.backgroundColor = UIColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1.0)
        assetPlaceholderIconImageView.bounds.size = CGSize(width: iconSize * 0.2, height: iconSize * 0.2)
        assetPlaceholderIconImageView.center = CGPoint(x: assetContainerView.bounds.midX, y: assetContainerView.bounds.midY)
        assetPlaceholderIconImageView.alpha = 1.0
    }
    
    func setTextColor() {
        if let pageTextLabel = pageTextLabel { pageTextLabel.textColor = color.fontColor() }
        if let placeholderView = textLabelPlaceholderBoxView {
            placeholderView.color = color
            placeholderView.setNeedsDisplay()
        }
    }
    
    @objc private func didTapOnPage(_ sender: UITapGestureRecognizer) {
        guard let index = pageIndex else { return }
        delegate?.didTapOnPage?(self, at: index)
    }
    
    @objc private func didTapOnAsset(_ sender: UITapGestureRecognizer) {
        guard let index = pageIndex else { return }
        delegate?.didTapOnAsset?(at: index)
    }

    @objc private func didTapOnText(_ sender: UITapGestureRecognizer) {
        guard let index = pageIndex else { return }
        delegate?.didTapOnText?(at: index)
    }

}
