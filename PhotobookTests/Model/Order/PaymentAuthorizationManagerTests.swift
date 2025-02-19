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

import XCTest
import PassKit
@testable import Photobook

class PaymentAuthorizationManagerTests: XCTestCase {
    
    var delegate: PaymentAuthorizationManagerDelegateMock!
    var paymentAuthorizationManager: PaymentAuthorizationManager!
    
    func fakeOrder() -> OrderMock {
        let order = OrderMock()
        
        let deliveryDetails = OLDeliveryDetails()
        deliveryDetails.firstName = "George"
        deliveryDetails.lastName = "Clowney"
        deliveryDetails.email = "g.clowney@clownmail.com"
        deliveryDetails.phone = "399945528234"
        deliveryDetails.line1 = "9 Fiesta Place"
        deliveryDetails.city = "London"
        deliveryDetails.zipOrPostcode = "CL0 WN4"
        deliveryDetails.stateOrCounty = "Clownborough"

        order.deliveryDetails = deliveryDetails
        return order
    }
    
    func fakeCost() -> Cost {
        let lineItem = LineItem(templateId: "hdbook_127x127", name: "item", price: Price(currencyCode: "GBP", value: 20), identifier: "")
        
        return Cost(hash: 1, lineItems: [lineItem], totalShippingPrice: Price(currencyCode: "GBP", value: 7), total: Price(currencyCode: "GBP", value: 27), promoDiscount: nil, promoCodeInvalidReason: nil)
    }
    
    override func setUp() {
        PaymentAuthorizationManager.applePayMerchantId = "ClownMasterId"
        
        delegate = PaymentAuthorizationManagerDelegateMock()
        
        paymentAuthorizationManager = PaymentAuthorizationManager()
        paymentAuthorizationManager.basketOrder = fakeOrder()
        paymentAuthorizationManager.delegate = delegate
    }
    
    func testAuthorizePayment_applePay_shouldCrashWithoutMerchantId() {
        PaymentAuthorizationManager.applePayMerchantId = nil

        expectFatalError(expectedMessage: "Missing merchant ID for ApplePay: PhotobookSDK.shared.applePayMerchantID") {
            self.paymentAuthorizationManager.authorizePayment(cost: self.fakeCost(), method: .applePay)
        }
    }
    
    func testAuthorizePayment_applePay_shouldPresentAuthorizationController() {
        paymentAuthorizationManager.authorizePayment(cost: fakeCost(), method: .applePay)

        XCTAssertTrue(delegate.viewControllerToPresent != nil && delegate.viewControllerToPresent! is PKPaymentAuthorizationViewController)
    }
    
    func testAuthorizePayment_payPal_shouldPresentPaypalController() {
        paymentAuthorizationManager.authorizePayment(cost: fakeCost(), method: .payPal)
        
        XCTAssertTrue(delegate.viewControllerToPresent != nil)
    }
}
