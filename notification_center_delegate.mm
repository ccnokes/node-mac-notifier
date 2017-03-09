#include "notification_center_delegate.h"

struct NotificationActivationInfo {
  Nan::Callback *callback;
  bool isReply;
  std::string response;
  std::string id;
  bool isClose;
};

@implementation NotificationCenterDelegate

static void DeleteAsyncHandle(uv_handle_t *handle) {
  delete (uv_async_t *)handle;
}

/**
 * This handler runs in the V8 context as a result of `uv_async_send`. Here we
 * retrieve our event information and invoke the saved callback.
 */
static void AsyncSendHandler(uv_async_t *handle) {
  Nan::HandleScope scope;
  auto *info = static_cast<NotificationActivationInfo *>(handle->data);

  // NSLog(@"Invoked notification with id: %s", info->id);

  v8::Local<v8::Value> argv[4] = {
    Nan::New(info->isReply),
    Nan::New(info->response).ToLocalChecked(),
    Nan::New(info->id).ToLocalChecked(),
    Nan::New(info->isClose),
  };

  info->callback->Call(4, argv);
  
  delete info;
  info = nullptr;
  handle->data = nullptr;
  uv_close((uv_handle_t *)handle, DeleteAsyncHandle);
}

/**
 * We save off the JavaScript callback here and initialize the libuv event
 * loop, which is needed in order to invoke the callback.
 */
- (id)initWithActivationCallback:(Nan::Callback *)onActivation
{
  if (self = [super init]) {
    OnActivation = onActivation;
  }
  
  return self;
}

// handles didActivateNotification & didDismissAlert
- (void) handleNotification:(NSUserNotification *)notification
          isClose:(bool)isClose 
{
  auto *info = new NotificationActivationInfo();
  info->isReply = notification.activationType == NSUserNotificationActivationTypeReplied;
  info->id = notification.identifier.UTF8String;
  info->callback = OnActivation;
  info->isClose = isClose;

  if (info->isReply) {
    info->response = notification.response.string.UTF8String;
  } else {
    info->response = "";
  }

  auto *async = new uv_async_t();
  async->data = info;
  uv_async_init(uv_default_loop(), async, (uv_async_cb)AsyncSendHandler);
  uv_async_send(async);
}

/**
 * Occurs when the user activates a notification by clicking it or replying.
 */
- (void)userNotificationCenter:(NSUserNotificationCenter *)center
       didActivateNotification:(NSUserNotification *)notification
{
  bool isClose = false;

  switch(notification.activationType) {
    // Not sure when this is true
    case NSUserNotificationActivationTypeNone:
      break;

    // Top level alternate action button clicked
    case NSUserNotificationActivationTypeActionButtonClicked:
      isClose = true;
      break;

    // Not in use currently by this lib but could be in the future
    case NSUserNotificationActivationTypeAdditionalActionClicked:
      break;

    case NSUserNotificationActivationTypeContentsClicked: // General notification area clicked
    case NSUserNotificationActivationTypeReplied: // Reply button clicked and sent
      isClose = false;
      break;
  }
  
  [self handleNotification:notification isClose:isClose];
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center
    shouldPresentNotification:(NSUserNotification *)notification
{
  return YES;
}

// This is an undocumented method that we need to be notified if a user clicks the close button.
- (void)userNotificationCenter:(NSUserNotificationCenter *)center
    didDismissAlert:(NSUserNotification *)notification
{
  [self handleNotification:notification isClose:!(notification.activationType == NSUserNotificationActivationTypeReplied)];
}

@end
