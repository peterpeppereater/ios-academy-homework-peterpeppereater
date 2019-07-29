//
//  LoginViewController.swift
//  TVShows
//
//  Created by Infinum on 05/07/2019.
//  Copyright © 2019 Infinum Academy. All rights reserved.
//

import UIKit
import SVProgressHUD
import Alamofire
import CodableAlamofire
import PromiseKit

final class LoginViewController: UIViewController {
    
    //MARK :- Outlets
    
    @IBOutlet private weak var rememberMeCheckboxButton: UIButton!
    @IBOutlet private weak var logInButton: UIButton!
    @IBOutlet private weak var scrollView: UIScrollView!
    @IBOutlet private weak var mainStackView: UIStackView!
    @IBOutlet private weak var usernameTextField: UITextField!
    @IBOutlet private weak var passwordTextField: UITextField!
    
    //MARK :- Properties
    
    private var rememberMeIsSelected: Bool = false
    private var topInsetValue: CGFloat = 0
    private var notificaionTokens: [NSObjectProtocol] = []
    
    //MARK :- Lifecycle methods

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        handleKeyboardEvents()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        setTopInsetValue()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    
    private func configureUI() {
        logInButton.layer.cornerRadius = 10
        //Set up a tap listener that dismisses the keyboard upon tapping outside text fields
        let tap = UITapGestureRecognizer(
            target: self.view,
            action: #selector(UIView.endEditing(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }
    
    deinit {
        notificaionTokens.forEach(NotificationCenter.default.removeObserver)
    }
    
    //Doing this keeps the content of the scroll view centered on all devices
    //TODO: Change this so it checks if it actually needs to change insets or not -> check if contentH - screenH >= keyboardH
    private func setTopInsetValue() {
        if mainStackView.frame.height < scrollView.frame.height //Content is smaller than scrollView so it needs to be centered on screen
        {
            topInsetValue = (scrollView.frame.height - mainStackView.frame.height)/2
            scrollView.contentInset.top = topInsetValue
        }
        else { //Content is bigger than scrollView so we remove the inset
            scrollView.contentInset.top = 0
        }
    }
    
    //MARK :- Actions
    
    @IBAction private func checkboxStateChanged() {
        rememberMeCheckboxButton.isSelected.toggle()
    }
    
    private func handleKeyboardEvents() {
        let willShowToken = NotificationCenter
            .default
            .addObserver(
                forName: UIResponder.keyboardWillShowNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let keyboardFrame: NSValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
                let keyboardRectangle = keyboardFrame.cgRectValue
                let keyboardHeight = keyboardRectangle.height
                self?.scrollView.contentInset.bottom = keyboardHeight
                self?.scrollView.contentInset.top = 0
            }
        let willHideToken = NotificationCenter
            .default
            .addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                // keyboard is about to hide, handle UIScrollView contentInset, e.g.
                self?.scrollView.contentInset.bottom = .zero
                guard let topInsetValue = self?.topInsetValue else { return }
                self?.scrollView.contentInset.top = topInsetValue
            }
        notificaionTokens.append(willShowToken)
        notificaionTokens.append(willHideToken)
    }

    //MARK: - Navigation
    
    private func navigateToHomeScene(loginData: LoginData) {
        let storyboard = UIStoryboard(name: "Home", bundle: nil)
        let homeViewController = storyboard.instantiateViewController(withIdentifier: "HomeViewController") as! HomeViewController
        homeViewController.userData = loginData
        navigationController?.pushViewController(homeViewController, animated: true)
    }
}

//MARK: - Helper functions

extension String {
    func isValidEmail() -> Bool {
        let regex = try! NSRegularExpression(
            pattern: "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}",
            options: .caseInsensitive)
        return regex.firstMatch(
            in: self,
            options: [],
            range: NSRange(location: 0, length: count)) != nil
    }
}

//MARK: - Animations

extension UITextField { //We shake the textbox with this one if fields are empty during acc creation
    func shake() {
        self.transform = CGAffineTransform(translationX: 20, y: 0)
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.2, initialSpringVelocity: 1, options: .curveEaseInOut, animations: {
            self.transform = CGAffineTransform.identity
        }, completion: nil)
    }
}

//MARK: - User authentication functions

extension LoginViewController {
    @IBAction func onLogin() {
        
        guard
            let userEmail = usernameTextField.text,
            let userPassword = passwordTextField.text
            else { return }
        
        let parameters: [String: String] = [
            "email": userEmail,
            "password": userPassword
        ]
        //No animations here since it's bad security praxis to tell the users whether the username or the password is wrong
        SVProgressHUD.show()
        //TODO: - Add "remember me" functionality
        //      Locally store user token once generated and first check if the token is valid I guess? Not sure how to check token against the web service sadly.
        firstly{
            APIManager.request(
                LoginData.self,
                path: "https://api.infinum.academy/api/users/sessions",
                method: .post,
                parameters: parameters,
                keyPath: "data",
                encoding: JSONEncoding.default,
                decoder: JSONDecoder())
            }.ensure {
                SVProgressHUD.dismiss()
            }.done { loginData in
                self.navigateToHomeScene(loginData: loginData)
            }.catch { [weak self] error in
                self?.showAlert(title: "Login error", message: "\(error.localizedDescription)")
        }
    }
    
    @IBAction func onAccountCreation() { //The API does check on the validity of inputs but if the call can be skipped I believe it should
        guard let userEmail = usernameTextField.text, let userPassword = passwordTextField.text else { return }
        if userEmail.isValidEmail(), !userPassword.isEmpty {
            
            SVProgressHUD.show()
            
            let parameters: [String: String] = [
                "email": userEmail,
                "password": userPassword
            ]
            
            firstly {
                APIManager.request(
                    User.self,
                    path: "https://api.infinum.academy/api/users",
                    method: .post,
                    parameters: parameters,
                    keyPath: "data",
                    encoding: JSONEncoding.default,
                    decoder: JSONDecoder())
                }.then { user -> Promise<LoginData> in
                    return APIManager.request(
                        LoginData.self,
                        path: "https://api.infinum.academy/api/users/sessions",
                        method: .post,
                        parameters: parameters,
                        keyPath: "data",
                        encoding: JSONEncoding.default,
                        decoder: JSONDecoder())
                }.ensure {
                    SVProgressHUD.dismiss()
                }.done { loginData in
                    self.navigateToHomeScene(loginData: loginData)
                }.catch{ [weak self] error in
                    self?.showAlert(title: "Login error", message: "\(error.localizedDescription)")
            }
        } else if !userEmail.isValidEmail() {
            usernameTextField.shake()
            showAlert(title: "Invalid username", message: "You must enter a valid e-mail")
        } else if userPassword.isEmpty {
            passwordTextField.shake()
            showAlert(title: "Password empty", message: "You must enter a password")
        }
    }
}

extension UIViewController {
    
    func showAlert(title: String, message: String) {
        let alertController = UIAlertController.init(
            title: "Error",
            message: "Something went wrong",
            preferredStyle: .alert)
        alertController.addAction(
            UIAlertAction.init(
                title: "OK",
                style: .default,
                handler: nil))
        present(alertController, animated: true, completion: nil)
    }
}
