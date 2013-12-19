/****************************************************************************
**
** Copyright (C) 2013 Klarälvdalens Datakonsult AB, a KDAB Group company, info@kdab.com, author Milian Wolff <milian.wolff@kdab.com>
** Contact: http://www.qt-project.org/legal
**
** This file is part of the QtWebChannel module of the Qt Toolkit.
**
** $QT_BEGIN_LICENSE:LGPL$
** No Commercial Usage
** This file contains pre-release code and may not be distributed.
** You may use this file in accordance with the terms and conditions
** contained in the Technology Preview License Agreement accompanying
** this package.
**
** GNU Lesser General Public License Usage
** Alternatively, this file may be used under the terms of the GNU Lesser
** General Public License version 2.1 as published by the Free Software
** Foundation and appearing in the file LICENSE.LGPL included in the
** packaging of this file.  Please review the following information to
** ensure the GNU Lesser General Public License version 2.1 requirements
** will be met: http://www.gnu.org/licenses/old-licenses/lgpl-2.1.html.
**
** In addition, as a special exception, Nokia gives you certain additional
** rights.  These rights are described in the Nokia Qt LGPL Exception
** version 1.1, included in the file LGPL_EXCEPTION.txt in this package.
**
** If you have questions regarding the use of this file, please contact
** Nokia at qt-info@nokia.com.
**
** $QT_END_LICENSE$
**
****************************************************************************/

import QtQuick 2.0

import QtWebChannel 1.0

WebChannelTest {
    name: "MetaObjectPublisher"
    id: test

    property var lastMethodArg

    QtObject {
        id: myObj
        property int myProperty: 1

        signal mySignal(var arg)

        function myMethod(arg)
        {
            lastMethodArg = arg;
        }
    }
    QtObject {
        id: myOtherObj
        property var foo: 1
        property var bar: 1
    }
    QtObject {
        id: myFactory
        property var lastObj
        function create(id)
        {
            lastObj = component.createObject(myFactory, {objectName: id});
            return lastObj;
        }
    }

    Component {
        id: component
        QtObject {
            property var myProperty : 0
            function myMethod(arg) {
                mySignal(arg, myProperty);
            }
            signal mySignal(var arg1, var arg2)
        }
    }

    MetaObjectPublisher {
        id: publisher
        webChannel: test.webChannel
    }

    Connections {
        target: test.webChannel
        onRawMessageReceived: {
            var message = JSON.parse(rawMessage);
            verify(message);
            var handled = publisher.handleRequest(message);
            if (message.data && message.data.type) {
                verify(handled);
            }
        }
    }

    function initTestCase()
    {
        publisher.registerObjects({
            "myObj": myObj,
            "myOtherObj": myOtherObj,
            "myFactory": myFactory
        });
    }

    function awaitInit()
    {
        var msg = awaitMessage();
        verify(msg);
        verify(msg.data);
        verify(msg.data.type);
        compare(msg.data.type, "Qt.init");
    }

    function awaitIdle()
    {
        var msg = awaitMessage();
        verify(msg);
        verify(msg.data);
        compare(msg.data.type, "Qt.idle");
        verify(publisher.test_clientIsIdle())
    }

    function awaitMessageSkipIdle()
    {
        var msg;
        do {
            msg = awaitMessage();
            verify(msg);
            verify(msg.data);
        } while (msg.data.type === "Qt.idle");
        return msg;
    }

    function test_property()
    {
        myObj.myProperty = 1
        loadUrl("property.html");
        awaitInit();
        var msg = awaitMessage();
        compare(msg.data.label, "init");
        compare(msg.data.value, 1);
        compare(myObj.myProperty, 1);

        awaitIdle();

        // change property, should be propagated to HTML client and a message be send there
        myObj.myProperty = 2;
        msg = awaitMessage();
        compare(msg.data.label, "changed");
        compare(msg.data.value, 2);
        compare(myObj.myProperty, 2);

        awaitIdle();

        // now trigger a write from the client side
        webChannel.sendMessage("setProperty", 3);
        msg = awaitMessage();
        compare(myObj.myProperty, 3);

        // the above write is also propagated to the HTML client
        msg = awaitMessage();
        compare(msg.data.label, "changed");
        compare(msg.data.value, 3);

        awaitIdle();
    }

    function test_method()
    {
        loadUrl("method.html");
        awaitInit();
        awaitIdle();

        webChannel.sendMessage("invokeMethod", "test");

        var msg = awaitMessage();
        compare(msg.data.type, "Qt.invokeMethod");
        compare(msg.data.object, "myObj");
        compare(msg.data.args, ["test"]);

        compare(lastMethodArg, "test")
    }

    function test_signal()
    {
        loadUrl("signal.html");
        awaitInit();

        var msg = awaitMessage();
        compare(msg.data.type, "Qt.connectToSignal");
        compare(msg.data.object, "myObj");

        awaitIdle();

        myObj.mySignal("test");

        msg = awaitMessage();
        compare(msg.data.label, "signalReceived");
        compare(msg.data.value, "test");
    }

    function test_grouping()
    {
        loadUrl("grouping.html");
        awaitInit();
        awaitIdle();

        // change properties a lot, we expect this to be grouped into a single update notification
        for (var i = 0; i < 10; ++i) {
            myObj.myProperty = i;
            myOtherObj.foo = i;
            myOtherObj.bar = i;
        }

        var msg = awaitMessage();
        verify(msg);
        compare(msg.data.label, "gotPropertyUpdate");
        compare(msg.data.values, [myObj.myProperty, myOtherObj.foo, myOtherObj.bar]);

        awaitIdle();
    }

    function test_wrapper()
    {
        loadUrl("wrapper.html");
        awaitInit();

        var msg = awaitMessageSkipIdle();
        compare(msg.data.type, "Qt.invokeMethod");
        compare(msg.data.object, "myFactory");
        verify(myFactory.lastObj);
        compare(myFactory.lastObj.objectName, "testObj");

        msg = awaitMessageSkipIdle();
        compare(msg.data.type, "Qt.connectToSignal");
        verify(msg.data.object);
        var objId = msg.data.object;

        msg = awaitMessageSkipIdle();
        compare(msg.data.type, "Qt.connectToSignal");
        compare(msg.data.object, objId);

        msg = awaitMessageSkipIdle();
        compare(msg.data.type, "Qt.setProperty");
        compare(msg.data.object, objId);
        compare(myFactory.lastObj.myProperty, 42);

        msg = awaitMessageSkipIdle();
        compare(msg.data.type, "Qt.invokeMethod");
        compare(msg.data.object, objId);
        compare(msg.data.args, ["foobar"]);

        msg = awaitMessageSkipIdle();
        compare(msg.data.label, "signalReceived");
        compare(msg.data.args, ["foobar", 42]);

        // pass QObject* on the fly and trigger deleteLater from client side
        webChannel.sendMessage("triggerDelete");

        msg = awaitMessageSkipIdle();
        compare(msg.data.type, "Qt.invokeMethod");
        compare(msg.data.object, objId);

        webChannel.sendMessage("report");

        msg = awaitMessageSkipIdle();
        compare(msg.data.label, "report");
        compare(msg.data.obj, {});
    }

    function test_disconnect()
    {
        loadUrl("disconnect.html");
        awaitInit();

        var msg = awaitMessage();
        compare(msg.data.type, "Qt.connectToSignal");
        compare(msg.data.object, "myObj");

        awaitIdle();

        myObj.mySignal(42);

        msg = awaitMessage();
        compare(msg.data.label, "mySignalReceived");
        compare(msg.data.args, [42]);

        msg = awaitMessage();
        compare(msg.data.type, "Qt.disconnectFromSignal");
        compare(msg.data.object, "myObj");

        myObj.mySignal(0);

        // apparently one cannot expect failure in QML, so trigger another message
        // and verify no mySignalReceived was triggered by the above emission
        webChannel.sendMessage("report");

        msg = awaitMessage();
        compare(msg.data.label, "report");
    }
}