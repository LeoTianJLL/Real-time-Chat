/*
* Copyright (c) 2015 Razeware LLC
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
* THE SOFTWARE.
*/

import UIKit
import Firebase
import JSQMessagesViewController


class ChatViewController: JSQMessagesViewController {
  
    // MARK: Properties
    var messages = [JSQMessage]()
    var userIsTypingRef: Firebase! // 1 Create a reference that tracks whether the local user is typing.
    private var localTyping = false // 2 Store whether the local user is typing in a private property.
    var isTyping: Bool {
        
        get {
            return localTyping
        }
        set {
            
            // 3 Using a computed property, you can update userIsTypingRef each time you update this property.
            localTyping = newValue
            userIsTypingRef.setValue(newValue)
            
        }
        
    }
    var usersTypingQuery: FQuery!
    
    let rootRef = Firebase(url: "https://emily-realtime-chat.firebaseio.com/")
    var messageRef: Firebase!
    
    var outgoingBubbleImageView: JSQMessagesBubbleImage!
    var incomingBubbleImageView: JSQMessagesBubbleImage!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "ChatChat"
        setupBubbles()
        // NO Avatars
        collectionView!.collectionViewLayout.incomingAvatarViewSize = CGSizeZero
        collectionView!.collectionViewLayout.outgoingAvatarViewSize = CGSizeZero
        
        messageRef = rootRef.childByAppendingPath("messages")
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        observeMessages()
        observeTyping()
    }
  
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
    }
  
    override func collectionView(collectionView: JSQMessagesCollectionView!, messageDataForItemAtIndexPath indexPath: NSIndexPath!) -> JSQMessageData! {
        
        return messages[indexPath.item]
        
    }
    
    override func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        
        return messages.count
    }
    
    override func collectionView(collectionView: JSQMessagesCollectionView!, avatarImageDataForItemAtIndexPath indexPath: NSIndexPath!) -> JSQMessageAvatarImageDataSource! {
        return nil
    }
    
    override func collectionView(collectionView: JSQMessagesCollectionView!, messageBubbleImageDataForItemAtIndexPath indexPath: NSIndexPath!) -> JSQMessageBubbleImageDataSource! {
        
        let message = messages[indexPath.item] // 1 Here you retrieve the message based on the NSIndexPath item.
        
        if message.senderId == senderId{ // 2 Check if the message was sent by the local user. If so, return the outgoing image view.
            return outgoingBubbleImageView
        }else{ // 3 If the message was not sent by the local user, return the incoming image view.
            return incomingBubbleImageView
        }
        
    }
    
    override func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        let cell = super.collectionView(collectionView, cellForItemAtIndexPath: indexPath) as! JSQMessagesCollectionViewCell
        
        let message = messages[indexPath.item]
        
        if message.senderId == senderId{
            cell.textView!.textColor = UIColor.whiteColor()
        }else{
            cell.textView!.textColor = UIColor.blackColor()
        }
        
        return cell
    }

    override func didPressSendButton(button: UIButton!, withMessageText text: String!, senderId: String!, senderDisplayName: String!, date: NSDate!) {
        
        let itemRef = messageRef.childByAutoId() // 1 Using childByAutoId(), you create a child reference with a unique key.
        
        print("itemRef id = \(itemRef.key)")
        
        let messageItem = ["text": text, "senderId": senderId] // 2 Create a dictionary to represent the message. A [String: AnyObject] works as a JSON-like object.
        
        itemRef.setValue(messageItem) // 3 Save the value at the new child location.
        
        JSQSystemSoundPlayer.jsq_playMessageSentSound() // 4 Play the canonical “message sent” sound.
        
        finishSendingMessage() // 5 Complete the “send” action and reset the input toolbar to empty.
        
        isTyping = false
    }
    
    override func textViewDidChange(textView:UITextView){
        super.textViewDidChange(textView)
        
        isTyping = textView.text != ""
    }
    
    
    private func setupBubbles() {
        
        let factory = JSQMessagesBubbleImageFactory()
        outgoingBubbleImageView = factory.outgoingMessagesBubbleImageWithColor(UIColor.jsq_messageBubbleBlueColor())
        incomingBubbleImageView = factory.incomingMessagesBubbleImageWithColor(UIColor.jsq_messageBubbleLightGrayColor())
        
    }
    
    
    private func observeMessages() {
        
        // 1 Start by creating a query that limits the synchronization to the last 25 messages.
        let messagesQuery = messageRef.queryLimitedToLast(25)
        
        // 2 Use the .ChildAdded event to observe for every child item that has been added, and will be added, at the messages location.
        messagesQuery.observeEventType(.ChildAdded) { (snapshot: FDataSnapshot!) in
            
            // 3 Extract the senderId and text from snapshot.value.
            let id = snapshot.value["senderId"] as! String
            let text = snapshot.value["text"] as! String
            
            // 4 Call addMessage() to add the new message to the data source.
            self.addMessage(id, text: text)
            
            // 5 Inform JSQMessagesViewController that a message has been received.
            self.finishReceivingMessage()
            
        }
    }
    
    private func observeTyping() {
        
        let typingIndicatorRef = rootRef.childByAppendingPath("typingIndicator")
        userIsTypingRef = typingIndicatorRef.childByAppendingPath(senderId)
        userIsTypingRef.onDisconnectRemoveValue()
        
        // 1 You initialize the query by retrieving all users who are typing. This is basically saying, “Hey Firebase, go to the key /typingIndicators and get me all users for whom the value is true.”
        usersTypingQuery = typingIndicatorRef.queryOrderedByValue().queryEqualToValue(true)
        
        // 2 Observe for changes using .Value; this will give you an update anytime anything changes.
        usersTypingQuery.observeEventType(.Value) { (data: FDataSnapshot!) in
        
            // 3 You need to see how many users are in the query. If the there’s just one user, check to see if the local user is typing. If so, don’t display the indicator.
            if data.childrenCount == 1 && self.isTyping {
                return
            }
            
            // 4 If there are more than zero users, and the local user isn’t typing, it’s safe to set the indicator. Call scrollToBottomAnimated(_:animated:) to ensure the indicator is displayed.
            self.showTypingIndicator = data.childrenCount > 0
            self.scrollToBottomAnimated(true)
        }
    }
    
    func addMessage(id:String, text:String){
        
        let message = JSQMessage(senderId:id, displayName: "", text: text)
        messages.append(message)
        
    }
    
    
    
    
    
}