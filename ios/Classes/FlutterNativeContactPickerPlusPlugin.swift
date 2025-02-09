import Flutter
import UIKit
import ContactsUI



class PickerHandler: NSObject, CNContactPickerDelegate  {
    var result: FlutterResult;
    
    required init(result: @escaping FlutterResult) {
        self.result = result
        super.init()
    }
    
    
    @available(iOS 9.0, *)
    public func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        result(nil)
    }
}

class SinglePickerHandler: PickerHandler {
    @available(iOS 9.0, *)
    public func contactPicker(_ picker: CNContactPickerViewController, didSelect partialContact: CNContact) {

        // We got a partial contact; let's refetch it fully from the store:
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, error in
            if let error = error {
                print("Error requesting access: \(error)")
                return
            }
            if granted {
                // Now safe to fetch
            } else {
                print("Access denied by user.")
            }
        }
        do {
            // We want all keys required by VCard serialization
            let keys = [CNContactVCardSerialization.descriptorForRequiredKeys()] as [Any]
            
            // Fetch the fully populated contact using the identifier
            let fullContact = try store.unifiedContact(
                withIdentifier: partialContact.identifier,
                keysToFetch: keys as! [CNKeyDescriptor]
            )
            
            // Now we can safely get the name/phone from this full contact
            var data = [String: Any]()
            data["fullName"] = CNContactFormatter.string(from: fullContact, style: .fullName)

            let numbers: [String] = fullContact.phoneNumbers.compactMap {
                $0.value.stringValue
            }
            data["phoneNumbers"] = numbers

            // Attempt vCard serialization again, but this time on the fully fetched contact
            let vCardData = try CNContactVCardSerialization.data(with: [fullContact])
            if let vcfString = String(data: vCardData, encoding: .utf8) {
                data["vcf"] = vcfString
                print("VCF is: \(vcfString)")
            }

            // Send result back to Flutter
            result(data)

        } catch {
            print("Error creating vCard or fetching full contact: \(error)")
            // Return at least the partial info we already have if you like
            var data = [String: Any]()
            data["fullName"] = CNContactFormatter.string(from: partialContact, style: .fullName)
            data["phoneNumbers"] = partialContact.phoneNumbers.compactMap {
                $0.value.stringValue
            }
            data["vcf"] = nil  // or omit
            result(data)
        }
    }
}

class MultiPickerHandler: PickerHandler {
    @available(iOS 9.0, *)
    public func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
        var selectedContacts = [Dictionary<String, Any>]()

         for contact in contacts {
             var contactInfo = Dictionary<String, Any>()
             contactInfo["fullName"] = CNContactFormatter.string(from: contact, style: CNContactFormatterStyle.fullName)

             let numbers: [String] = contact.phoneNumbers.compactMap { $0.value.stringValue as String }
             contactInfo["phoneNumbers"] = numbers

            do {
                let vCardData = try CNContactVCardSerialization.data(with: [contact])
                if var vcfString = String(data: vCardData, encoding: .utf8) {
                    contactInfo["vcf"] = vcfString
                   
                }
            } catch {
                print("Error creating vCard: \(error)")
                // Handle error as needed
            }
 
             selectedContacts.append(contactInfo)
         }

         result(selectedContacts)
    }
}


public class SwiftFlutterNativeContactPickerPlusPlugin: NSObject, FlutterPlugin , CNContactPickerDelegate{
    
var _delegate: PickerHandler?;

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_native_contact_picker_plus", binaryMessenger: registrar.messenger())
    let instance = SwiftFlutterNativeContactPickerPlusPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      if("selectContact" == call.method || "selectContacts" == call.method) {
        if(_delegate != nil) {
            _delegate!.result(FlutterError(code: "multiple_requests", message: "Cancelled by a second request.", details: nil));
            _delegate = nil;
          }

          if #available(iOS 9.0, *){
              let single = call.method == "selectContact";
              _delegate = single ? SinglePickerHandler(result: result) : MultiPickerHandler(result: result);
              let contactPicker = CNContactPickerViewController()
              contactPicker.delegate = _delegate
              contactPicker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
              
              // find proper keyWindow
              var keyWindow: UIWindow? = nil
              if #available(iOS 13, *) {
                  keyWindow = UIApplication.shared.connectedScenes.filter {
                      $0.activationState == .foregroundActive
                  }.compactMap { $0 as? UIWindowScene
                  }.first?.windows.filter({ $0.isKeyWindow}).first
              } else {
                  keyWindow = UIApplication.shared.keyWindow
              }
              
              let viewController = keyWindow?.rootViewController
              viewController?.present(contactPicker, animated: true, completion: nil)
          }
      }
       else
          {
              result(FlutterMethodNotImplemented)
          }
    }

}
