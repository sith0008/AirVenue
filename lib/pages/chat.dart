import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:krisbook/pages/const.dart';
import 'package:translator/translator.dart';

class Chat extends StatelessWidget {
  final String peerId;
  final String peerName;
  @override
  Chat({Key key, @required this.peerId, @required this.peerName})
      : super(key: key);

  bool translate = false;

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: new Text(peerName),
        backgroundColor: new Color(0xFF1D4886),
        elevation: Theme.of(context).platform == TargetPlatform.iOS ? 0.0 : 6.0,
      ),
      body: new ChatScreen(
        peerId: peerId,
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String peerId;

  ChatScreen({Key key, @required this.peerId}) : super(key: key);

  @override
  State createState() => new ChatScreenState(peerId: peerId);
}

class ChatScreenState extends State<ChatScreen> {
  ChatScreenState({Key key, @required this.peerId});

  String peerId;
  String id;
  var listMessage;
  String groupChatId;
  SharedPreferences prefs;

  static const platform = const MethodChannel("flutter.io/chatbot");

  File imageFile;
  bool isLoading;
  bool isShowSticker;
  String imageUrl;

  final TextEditingController textEditingController =
      new TextEditingController();
  final ScrollController listScrollController = new ScrollController();
  final FocusNode focusNode = new FocusNode();

  @override
  void initState() {
    super.initState();
    focusNode.addListener(onFocusChange);

    groupChatId = '';

    isLoading = false;
    isShowSticker = false;
    imageUrl = '';

    readLocal();
  }

  void onFocusChange() {
    if (focusNode.hasFocus) {
      // Hide sticker when keyboard appear
      setState(() {
        isShowSticker = false;
      });
    }
  }

  readLocal() async {
    prefs = await SharedPreferences.getInstance();
    id = prefs.getString('id') ?? '';
    if (id.hashCode <= peerId.hashCode) {
      groupChatId = '$id-$peerId';
    } else {
      groupChatId = '$peerId-$id';
    }

    setState(() {});
  }

  void getSticker() {
    // Hide keyboard when sticker appear
    focusNode.unfocus();
    setState(() {
      isShowSticker = !isShowSticker;
    });
  }

  Future getImage() async {
    File image = await ImagePicker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      setState(() {
        imageFile = image;
        isLoading = true;
      });
    }
    uploadFile();
  }

  Future uploadFile() async {
    String fileName = DateTime.now().millisecondsSinceEpoch.toString();
    StorageReference reference = FirebaseStorage.instance.ref().child(fileName);
    StorageUploadTask uploadTask = reference.putFile(imageFile);

    Uri downloadUrl = (await uploadTask.future).downloadUrl;
    imageUrl = downloadUrl.toString();

    setState(() {
      isLoading = false;
    });

    onSendMessage(
        imageUrl, 1, getPeerIdLang(), getLang(), getWantsTranslation());
  }

  String peerLang;
  getPeerIdLang() {
    DocumentReference userRef =
        Firestore.instance.collection('users').document(peerId);
    userRef
        .get()
        .then((snapshot) => peerLang = snapshot['Languages1'])
        .whenComplete(() {
      if (peerLang == 'German') {
        peerLang = "de";
      } else if (peerLang == 'English') {
        peerLang = 'en';
      } else if (peerLang == 'French') {
        peerLang = 'fr';
      } else if (peerLang == 'Italian') {
        peerLang = 'it';
      }
      return peerLang;
    }).catchError((e) => print(e));
  }

  String ownLang;
  String getLang() {
    DocumentReference userRef =
        Firestore.instance.collection('users').document(id);
    userRef.get().then((snapshot) {
      ownLang = snapshot['Languages1'];
    }).whenComplete(() {
      if (ownLang == 'German') {
        ownLang = "de";
      } else if (ownLang == 'English') {
        ownLang = 'en';
      } else if (peerLang == 'French') {
        peerLang = 'fr';
      } else if (peerLang == 'Italian') {
        peerLang = 'it';
      }
      return ownLang;
    }).catchError((e) => print(e));
    return ownLang;
  }

  String ownTranslation;
  getOwnTranslation() {
    DocumentReference userRef =
        Firestore.instance.collection('users').document(id);
    userRef
        .get()
        .then((snapshot) => ownTranslation = snapshot['wantsTranslation'])
        .whenComplete(() {
      //print(ownTranslation);
      return ownTranslation;
    }).catchError((e) => print(e));
    return ownTranslation;
  }

  String peerTranslation;
  getWantsTranslation() {
    DocumentReference userRef =
        Firestore.instance.collection('users').document(peerId);
    userRef
        .get()
        .then((snapshot) => peerTranslation = snapshot['wantsTranslation'])
        .whenComplete(() {
      //print(wantsTranslation);
      return peerTranslation;
    }).catchError((e) => print(e));
    return peerTranslation;
  }

  bool enCheck;
  isFirstLangEnglish() {
    String lang;
    DocumentReference userRef =
        Firestore.instance.collection('users').document(id);
    userRef
        .get()
        .then((snapshot) => lang = snapshot['Languages1'])
        .whenComplete(() {
      if (lang == 'English') {
        enCheck = true;
      } else {
        enCheck = false;
      }
      return enCheck;
    }).catchError((e) => print(e));
  }

  GoogleTranslator translator = GoogleTranslator();
  void onSendMessage(String content, int type, String peerLang, String selfLang,
      String peerWantsTranslation) {
    // type: 0 = text, 1 = image, 2 = sticker
    var translated;
    var english;
    if (content.trim() != '') {
      textEditingController.clear();
      if (selfLang == 'en') {
        english = content;
        translator
            .translate(english, to: peerLang)
            .then((output) => translated = output)
            .whenComplete(() {
          print(translated);
          var documentReference = Firestore.instance
              .collection('chatMessages')
              .document(groupChatId)
              .collection(groupChatId)
              .document(DateTime.now().millisecondsSinceEpoch.toString());

          Firestore.instance.runTransaction((transaction) async {
            await transaction.set(
              documentReference,
              {
                'idFrom': id,
                'idTo': peerId,
                'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
                'translated_content': translated,
                'en_content': english,
                'type': type
              },
            );
          });
          listScrollController.animateTo(0.0,
              duration: Duration(milliseconds: 300), curve: Curves.easeOut);
        }).catchError((e) => print(e));
      } else {
        translated = content;
        translator
            .translate(content, to: 'en')
            .then((output) => english = output)
            .whenComplete(() {
          var documentReference = Firestore.instance
              .collection('chatMessages')
              .document(groupChatId)
              .collection(groupChatId)
              .document(DateTime.now().millisecondsSinceEpoch.toString());

          Firestore.instance.runTransaction((transaction) async {
            await transaction.set(
              documentReference,
              {
                'idFrom': id,
                'idTo': peerId,
                'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
                'translated_content': translated,
                'en_content': english,
                'type': type
              },
            );
          });
          listScrollController.animateTo(0.0,
              duration: Duration(milliseconds: 300), curve: Curves.easeOut);
        }).catchError((e) => print(e));
      }

      //Adding chatbot conversation here
      if (peerId == 'SIAchatbot') {
        //Send message to watson server
        _sendMessageToWatson(content);
      }
    } else {
      Fluttertoast.showToast(msg: 'Nothing to send');
    }
  }

  Future<Null> _sendMessageToWatson(String content) async {
    try {
      final String chatbotMessage = await platform
          .invokeMethod('getChatbotMessage', {'content': content});

      var documentReference = Firestore.instance
          .collection('chatMessages')
          .document(groupChatId)
          .collection(groupChatId)
          .document(DateTime.now().millisecondsSinceEpoch.toString());

      Firestore.instance.runTransaction((transaction) async {
        await transaction.set(
          documentReference,
          {
            'idFrom': 'SIAchatbot',
            'idTo': id,
            'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
            'content': chatbotMessage,
            'type': 0
          },
        );
      });
      listScrollController.animateTo(0.0,
          duration: Duration(milliseconds: 300), curve: Curves.easeOut);
    } catch (e) {}
  }

  Widget buildItem(int index, DocumentSnapshot document, bool enCheck,
      String ownTranslation) {
    if (document['idFrom'] == id) {
      // Right (my message)
      return Row(
        children: <Widget>[
          document['type'] == 0
              // Text
              ? Container(
                  child: enCheck
                      ? Text(
                          document['en_content'],
                          style: TextStyle(color: primaryColor),
                        )
                      : ownTranslation == "true"
                          ? Text(
                              document['translated_content'],
                              style: TextStyle(color: primaryColor),
                            )
                          : Text(
                              document['en_content'],
                              style: TextStyle(color: primaryColor),
                            ),
                  padding: EdgeInsets.fromLTRB(15.0, 10.0, 15.0, 10.0),
                  width: 200.0,
                  decoration: BoxDecoration(
                      color: greyColor2,
                      borderRadius: BorderRadius.circular(8.0)),
                  margin: EdgeInsets.only(
                      bottom: isLastMessageRight(index) ? 20.0 : 10.0,
                      right: 10.0),
                )
              : document['type'] == 1
                  // Image
                  ? Container(
                      child: Material(
                        child: CachedNetworkImage(
                          placeholder: Container(
                            child: CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(themeColor),
                            ),
                            width: 200.0,
                            height: 200.0,
                            padding: EdgeInsets.all(70.0),
                            decoration: BoxDecoration(
                              color: greyColor2,
                              borderRadius: BorderRadius.all(
                                Radius.circular(8.0),
                              ),
                            ),
                          ),
                          errorWidget: Material(
                            child: Image.asset(
                              'assets/buddy.jpeg', //TODO: Update with real pics
                              width: 200.0,
                              height: 200.0,
                              fit: BoxFit.cover,
                            ),
                            borderRadius: BorderRadius.all(
                              Radius.circular(8.0),
                            ),
                          ),
                          imageUrl: document['content'],
                          width: 200.0,
                          height: 200.0,
                          fit: BoxFit.cover,
                        ),
                        borderRadius: BorderRadius.all(Radius.circular(8.0)),
                      ),
                      margin: EdgeInsets.only(
                          bottom: isLastMessageRight(index) ? 20.0 : 10.0,
                          right: 10.0),
                    )
                  // Sticker
                  : Container(
                      child: new Image.asset(
                        'assets/${document['content']}.gif',
                        width: 100.0,
                        height: 100.0,
                        fit: BoxFit.cover,
                      ),
                      margin: EdgeInsets.only(
                          bottom: isLastMessageRight(index) ? 20.0 : 10.0,
                          right: 10.0),
                    ),
        ],
        mainAxisAlignment: MainAxisAlignment.end,
      );
    } else {
      // Left (peer message)
      return Container(
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                isLastMessageLeft(index)
                    ? Material(
                        child: CachedNetworkImage(
                          placeholder: Container(
                            child: CircularProgressIndicator(
                              strokeWidth: 1.0,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(themeColor),
                            ),
                            width: 35.0,
                            height: 35.0,
                            padding: EdgeInsets.all(10.0),
                          ),
                          imageUrl:
                              "https://cdn-images-1.medium.com/max/1200/1*5-aoK8IBmXve5whBQM90GA.png", // TODO: add link to pic here
                          width: 35.0,
                          height: 35.0,
                          fit: BoxFit.cover,
                        ),
                        borderRadius: BorderRadius.all(
                          Radius.circular(18.0),
                        ),
                      )
                    : Container(width: 35.0),
                document['type'] == 0
                    ? Container(
                        child: enCheck
                            ? Text(
                                document['en_content'],
                                style: TextStyle(color: Colors.white),
                              )
                            : ownTranslation == "true"
                                ? Text(
                                    document['translated_content'],
                                    style: TextStyle(color: Colors.white),
                                  )
                                : Text(
                                    document['en_content'],
                                    style: TextStyle(color: Colors.white),
                                  ),
                        padding: EdgeInsets.fromLTRB(15.0, 10.0, 15.0, 10.0),
                        width: 200.0,
                        decoration: BoxDecoration(
                            color: primaryColor,
                            borderRadius: BorderRadius.circular(8.0)),
                        margin: EdgeInsets.only(
                            bottom: isLastMessageRight(index) ? 20.0 : 10.0,
                            right: 10.0),
                      )
                    : document['type'] == 1
                        ? Container(
                            child: Material(
                              child: CachedNetworkImage(
                                placeholder: Container(
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        themeColor),
                                  ),
                                  width: 200.0,
                                  height: 200.0,
                                  padding: EdgeInsets.all(70.0),
                                  decoration: BoxDecoration(
                                    color: greyColor2,
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(8.0),
                                    ),
                                  ),
                                ),
                                errorWidget: Material(
                                  child: Image.asset(
                                    'assets/img_not_available.jpeg',
                                    width: 200.0,
                                    height: 200.0,
                                    fit: BoxFit.cover,
                                  ),
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(8.0),
                                  ),
                                ),
                                imageUrl: document['content'],
                                width: 200.0,
                                height: 200.0,
                                fit: BoxFit.cover,
                              ),
                              borderRadius:
                                  BorderRadius.all(Radius.circular(8.0)),
                            ),
                            margin: EdgeInsets.only(left: 10.0),
                          )
                        : Container(
                            child: new Image.asset(
                              'assets/${document['content']}.gif',
                              width: 100.0,
                              height: 100.0,
                              fit: BoxFit.cover,
                            ),
                            margin: EdgeInsets.only(
                                bottom: isLastMessageRight(index) ? 20.0 : 10.0,
                                right: 10.0),
                          ),
              ],
            ),

            // Time
            isLastMessageLeft(index)
                ? Container(
                    child: Text(
                      DateFormat('dd MMM kk:mm').format(
                          DateTime.fromMillisecondsSinceEpoch(
                              int.parse(document['timestamp']))),
                      style: TextStyle(
                          color: greyColor,
                          fontSize: 12.0,
                          fontStyle: FontStyle.italic),
                    ),
                    margin: EdgeInsets.only(left: 50.0, top: 5.0, bottom: 5.0),
                  )
                : Container()
          ],
          crossAxisAlignment: CrossAxisAlignment.start,
        ),
        margin: EdgeInsets.only(bottom: 10.0),
      );
    }
  }

  bool isLastMessageLeft(int index) {
    if ((index > 0 &&
            listMessage != null &&
            listMessage[index - 1]['idFrom'] == id) ||
        index == 0) {
      return true;
    } else {
      return false;
    }
  }

  bool isLastMessageRight(int index) {
    if ((index > 0 &&
            listMessage != null &&
            listMessage[index - 1]['idFrom'] != id) ||
        index == 0) {
      return true;
    } else {
      return false;
    }
  }

  Future<bool> onBackPress() {
    if (isShowSticker) {
      setState(() {
        isShowSticker = false;
      });
    } else {
      Navigator.pop(context);
    }

    return Future.value(false);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      child: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              // List of messages
              buildListMessage(),

              // Sticker
              (isShowSticker ? buildSticker() : Container()),

              // Input content
              buildInput(),
            ],
          ),

          // Loading
          buildLoading()
        ],
      ),
      onWillPop: onBackPress,
    );
  }

  Widget buildSticker() {
    return Container(
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              FlatButton(
                onPressed: () => onSendMessage('mimi1', 2, getPeerIdLang(),
                    getLang(), getWantsTranslation()),
                child: new Image.asset(
                  'assets/mimi1.gif',
                  width: 50.0,
                  height: 50.0,
                  fit: BoxFit.cover,
                ),
              ),
              FlatButton(
                onPressed: () => onSendMessage('mimi2', 2, getPeerIdLang(),
                    getLang(), getWantsTranslation()),
                child: new Image.asset(
                  'assets/mimi2.gif',
                  width: 50.0,
                  height: 50.0,
                  fit: BoxFit.cover,
                ),
              ),
              FlatButton(
                onPressed: () => onSendMessage('mimi3', 2, getPeerIdLang(),
                    getLang(), getWantsTranslation()),
                child: new Image.asset(
                  'assets/mimi3.gif',
                  width: 50.0,
                  height: 50.0,
                  fit: BoxFit.cover,
                ),
              )
            ],
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          ),
          Row(
            children: <Widget>[
              FlatButton(
                onPressed: () => onSendMessage('mimi4', 2, getPeerIdLang(),
                    getLang(), getWantsTranslation()),
                child: new Image.asset(
                  'assets/mimi4.gif',
                  width: 50.0,
                  height: 50.0,
                  fit: BoxFit.cover,
                ),
              ),
              FlatButton(
                onPressed: () => onSendMessage('mimi5', 2, getPeerIdLang(),
                    getLang(), getWantsTranslation()),
                child: new Image.asset(
                  'assets/mimi5.gif',
                  width: 50.0,
                  height: 50.0,
                  fit: BoxFit.cover,
                ),
              ),
              FlatButton(
                onPressed: () => onSendMessage('mimi6', 2, getPeerIdLang(),
                    getLang(), getWantsTranslation()),
                child: new Image.asset(
                  'assets/mimi6.gif',
                  width: 50.0,
                  height: 50.0,
                  fit: BoxFit.cover,
                ),
              )
            ],
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          ),
          Row(
            children: <Widget>[
              FlatButton(
                onPressed: () => onSendMessage('mimi7', 2, getPeerIdLang(),
                    getLang(), getWantsTranslation()),
                child: new Image.asset(
                  'assets/mimi7.gif',
                  width: 50.0,
                  height: 50.0,
                  fit: BoxFit.cover,
                ),
              ),
              FlatButton(
                onPressed: () => onSendMessage('mimi8', 2, getPeerIdLang(),
                    getLang(), getWantsTranslation()),
                child: new Image.asset(
                  'assets/mimi8.gif',
                  width: 50.0,
                  height: 50.0,
                  fit: BoxFit.cover,
                ),
              ),
              FlatButton(
                onPressed: () => onSendMessage('mimi9', 2, getPeerIdLang(),
                    getLang(), getWantsTranslation()),
                child: new Image.asset(
                  'assets/mimi9.gif',
                  width: 50.0,
                  height: 50.0,
                  fit: BoxFit.cover,
                ),
              )
            ],
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          )
        ],
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      ),
      decoration: new BoxDecoration(
          border:
              new Border(top: new BorderSide(color: greyColor2, width: 0.5)),
          color: Colors.white),
      padding: EdgeInsets.all(5.0),
      height: 180.0,
    );
  }

  Widget buildLoading() {
    return Positioned(
      child: isLoading
          ? Container(
              child: Center(
                child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(themeColor)),
              ),
              color: Colors.white.withOpacity(0.8),
            )
          : Container(),
    );
  }

  Widget buildInput() {
    return Container(
      child: Row(
        children: <Widget>[
          Material(
            child: new Container(
              margin: new EdgeInsets.symmetric(horizontal: 1.0),
              child: new IconButton(
                icon: new Icon(Icons.face),
                onPressed: getSticker,
              ),
            ),
            color: Colors.white,
          ),

          // Edit text
          Flexible(
            child: Container(
              child: TextField(
                style: TextStyle(color: primaryColor, fontSize: 15.0),
                controller: textEditingController,
                decoration: InputDecoration.collapsed(
                  hintText: 'Type your message...',
                  hintStyle: TextStyle(color: greyColor),
                ),
                focusNode: focusNode,
              ),
            ),
          ),

          // Button send message
          Material(
            child: new Container(
              child: new IconButton(
                icon: new Icon(Icons.send),
                onPressed: () {
                  getLang();
                  // print(ownLang);
                  getPeerIdLang();
                  // print(peerLang);
                  getWantsTranslation();
                  // print(peerTranslation);
                  onSendMessage(textEditingController.text, 0, peerLang,
                      ownLang, peerTranslation);
                },
              ),
            ),
            color: Colors.white,
          ),
        ],
      ),
      width: double.infinity,
      height: 50.0,
      decoration: new BoxDecoration(
          border:
              new Border(top: new BorderSide(color: greyColor2, width: 0.5)),
          color: Colors.white),
    );
  }

  Widget buildListMessage() {
    return Flexible(
      child: groupChatId == ''
          ? Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(themeColor)))
          : StreamBuilder(
              stream: Firestore.instance
                  .collection('chatMessages')
                  .document(groupChatId)
                  .collection(groupChatId)
                  .orderBy('timestamp', descending: true)
                  .limit(20)
                  .snapshots(),
              builder: (context, snapshot) {
                isFirstLangEnglish();
                getOwnTranslation();
                if (!snapshot.hasData) {
                  return Center(
                      child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(themeColor)));
                } else {
                  listMessage = snapshot.data.documents;
                  return ListView.builder(
                    padding: EdgeInsets.all(10.0),
                    itemBuilder: (context, index) => buildItem(
                        index,
                        snapshot.data.documents[index],
                        enCheck,
                        ownTranslation),
                    itemCount: snapshot.data.documents.length,
                    reverse: true,
                    controller: listScrollController,
                  );
                }
              },
            ),
    );
  }
}
