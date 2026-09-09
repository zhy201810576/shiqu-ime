## POST /auth/auth_code
summary: 获取auth_code，有效时间为24小时内
operationId: AppController_getAuthCode
security: []
requestBody required=True: {"application/json": {"schema": {"type": "object", "properties": {"refresh_token": {"type": "string", "description": "refresh_token（与api_key二选一）"}, "api_key": {"type": "string", "description": "API Key（与refresh_token二选一）"}}}}}
response200: {"description": "获取成功", "content": {"application/json": {"schema": {"type": "object", "properties": {"auth_code": {"type": "string", "description": "授权码"}}}}}}

## GET /gateway/recentFiles
summary: 最近添加的文件
operationId: GatewayControllerPart3_filesRecent
security: [{"api-key": []}, {"bearer": []}]
parameters:
  - galleryIds (in=query) required=True desc= schema={"type": "string"}
response200: {"description": "返回最近添加的文件列表", "content": {"application/json": {"schema": {"type": "array", "items": {"type": "object", "properties": {"id": {"type": "number", "description": "文件ID"}, "MD5": {"type": "string", "description": "文件MD5值"}, "fileName": {"type": "string", "description": "文件名"}, "filePath": {"type": "string", "description": "文件路径"}, "tokenAt": {"type": "string", "description": "拍摄时间"}}}}}}}

## GET /gateway/myGalleryList
summary: 用户的图库列表
operationId: GatewayController_userGalleryList
security: [{"api-key": []}, {"bearer": []}]
response200: {"description": "返回图库列表", "content": {"application/json": {"schema": {"type": "array", "items": {"type": "object", "properties": {"id": {"type": "number", "description": "图库ID"}, "name": {"type": "string", "description": "图库名称"}, "forUpload": {"type": "boolean", "description": "是否为备份专用图库", "nullable": true}, "multi": {"type": "boolean", "description": "是否支持多选", "nullable": true}}}}}}}

## GET /gateway/filesInTimeline
summary: 所有文件
operationId: GatewayController_findAllFiles
security: [{"api-key": []}, {"bearer": []}]
parameters:
  - _t (in=query) required=False desc=时间戳 schema={"type": "number"}
response200: {"description": "返回文件列表", "content": {"application/json": {"schema": {"type": "array", "items": {"type": "object", "properties": {"id": {"type": "number", "description": "文件ID"}, "MD5": {"type": "string", "description": "文件MD5值"}, "fileName": {"type": "string", "description": "文件名"}, "filePath": {"type": "string", "description": "文件路径"}, "tokenAt": {"type": "string", "description": "拍摄时间"}}}}}}}

## GET /gateway/filesInTimelineV2
summary: 所有文件-时间线
operationId: GatewayController_findAllFilesV2
security: [{"api-key": []}, {"bearer": []}]
parameters:
  - galleryIds (in=query) required=False desc=多个图库ID，用下划线分隔 schema={"type": "string"}
  - galleryId (in=query) required=False desc=单个图库ID schema={"type": "number"}
  - _t (in=query) required=False desc=时间戳 schema={"type": "number"}
response200: {"description": "返回文件列表", "content": {"application/json": {"schema": {"type": "array", "items": {"type": "object", "properties": {"id": {"type": "number", "description": "文件ID"}, "MD5": {"type": "string", "description": "文件MD5值"}, "fileName": {"type": "string", "description": "文件名"}, "tokenAt": {"type": "string", "description": "拍摄时间"}, "fileType": {"type": "string", "description": "文件类型"}}}}}}}

## POST /gateway/search
summary: 搜索
operationId: GatewayControllerPart5_searchFiles
security: [{"api-key": []}, {"bearer": []}]
requestBody required=True: {"application/json": {"schema": {"type": "object", "properties": {"key": {"type": "string"}, "model": {"type": "string"}, "lens": {"type": "string"}, "rating": {"type": "number"}, "tokenAtStart": {"type": "number"}, "tokenAtEnd": {"type": "number"}, "mtimeStart": {"type": "number"}, "mtimeEnd": {"type": "number"}, "widthMin": {"type": "number"}, "widthMax": {"type": "number"}, "heightMin": {"type": "number"}, "heightMax": {"type": "number"}}}}}
response200: {"description": "返回搜索结果", "content": {"application/json": {"schema": {"type": "object", "properties": {"result": {"type": "array", "description": "按日期分组的文件列表", "items": {"type": "object", "properties": {"date": {"type": "string"}, "files": {"type": "array"}}}}, "totalCount": {"type": "number"}, "list": {"type": "array", "description": "扁平化文件列表"}}}}}}

## GET /api-album
summary: 我的相册列表
operationId: AlbumController_findAll
security: [{"api-key": []}, {"bearer": []}]
response200: {"description": "返回相册列表", "content": {"application/json": {"schema": {"type": "array", "items": {"type": "object", "properties": {"id": {"type": "number", "description": "相册ID"}, "name": {"type": "string", "description": "相册名称"}, "desc": {"type": "string", "description": "相册描述"}, "cover": {"type": "string", "description": "封面MD5"}, "count": {"type": "number", "description": "文件数量"}, "mtime": {"type": "string", "format": "date-time", "description": "相册信息或文件变更时间"}, "create_time": {"type": "string", "format": "date-time", "description": "相册创建时间"}, "startTime": {"type": "string", "format": "date-time", "description": "开始时间"}, "endTime": {"type": "string", "format": "date-time", "description": "结束时间"}}}}}}}

## GET /api-album/files/{id}
summary: 相册文件列表
operationId: AlbumController_findAlbumFiles
security: [{"api-key": []}, {"bearer": []}]
parameters:
  - id (in=path) required=True desc=相册ID schema={"type": "number"}
response200: {"description": "返回文件列表（已废弃）", "content": {"application/json": {"schema": {"type": "array", "items": {"type": "object", "properties": {"id": {"type": "number", "description": "文件ID"}, "MD5": {"type": "string", "description": "文件MD5"}, "tokenAt": {"type": "string", "format": "date-time", "description": "拍摄时间"}}}}}}}

## POST /gateway/areaFilesMD5
summary: 根据文件ID列表获取文件信息
operationId: GatewayControllerPart4_getFileMD5List
security: [{"api-key": []}, {"bearer": []}]
requestBody required=True: {"application/json": {"schema": {"type": "object", "properties": {"ids": {"type": "array", "items": {"type": "number"}, "description": "文件ID列表"}, "albumId": {"type": "number", "description": "相册ID（可选）"}, "albumType": {"type": "string", "description": "相册类型，share 表示分享相册"}}}}}
response200: {"description": "返回文件MD5列表", "content": {"application/json": {"schema": {"type": "array", "items": {"type": "object", "properties": {"id": {"type": "number", "description": "文件ID"}, "MD5": {"type": "string", "description": "文件MD5值"}, "fileName": {"type": "string", "description": "文件名"}, "tokenAt": {"type": "number", "description": "拍摄时间戳"}, "duration": {"type": "number", "description": "视频时长", "nullable": true}}}}}}}

## POST /gateway/fileInIds
summary: 根据文件ID列表获取文件详情
operationId: GatewayControllerPart4_getFileInIds
security: [{"api-key": []}, {"bearer": []}]
requestBody required=True: {"application/json": {"schema": {"type": "object", "properties": {"ids": {"type": "array", "items": {"type": "number"}, "description": "文件ID列表"}, "albumId": {"type": "number", "description": "相册ID（可选）"}, "albumType": {"type": "string", "description": "相册类型，share 表示分享相册"}}}}}
response200: {"description": "返回文件详情列表（按日期分组）", "content": {"application/json": {"schema": {"type": "array", "items": {"type": "object", "properties": {"date": {"type": "string", "description": "日期"}, "files": {"type": "array", "items": {"type": "object", "properties": {"id": {"type": "number", "description": "文件ID"}, "MD5": {"type": "string", "description": "文件MD5值"}, "fileName": {"type": "string", "description": "文件名"}, "tokenAt": {"type": "string", "description": "拍摄时间"}}}}}}}}}}

## GET /gateway/{type}/{md5}
summary: 显示文件的缩略图
operationId: GatewayControllerPartEnd_renderThumb
security: [{"api-key": []}, {"bearer": []}]
parameters:
  - type (in=path) required=True desc=缩略图类型：h220-PC缩略图, s260-app缩略图, preview-视频前5s的动图, poster-视频封面 schema={"type": "string"}
  - md5 (in=path) required=True desc=文件MD5值 schema={"type": "string"}
  - albumId (in=query) required=False desc=相册ID，如果在相册内需要 schema={"type": "string"}
  - id (in=query) required=False desc=文件ID ，可选 schema={"type": "number"}
  - auth_code (in=query) required=True desc=授权码 schema={"type": "string"}
response200: {"description": "返回缩略图文件流"}

## GET /gateway/file/{id}/{md5}
summary: 显示文件原图
operationId: GatewayControllerPart2_renderFile
security: [{"api-key": []}, {"bearer": []}]
parameters:
  - id (in=path) required=True desc=文件ID schema={"type": "string"}
  - md5 (in=path) required=True desc=文件MD5值 schema={"type": "string"}
  - albumId (in=query) required=False desc=相册ID（可选） schema={"type": "number"}
  - auth_code (in=query) required=True desc=授权码 schema={"type": "string"}
  - type (in=query) required=False desc=类型：proxy-预览图、hd-高清预览图、ori-原图、transcode-视频的转码文件、motion-动态照片视频 schema={"type": "string"}
response200: {"description": "返回文件流"}

## GET /gateway/fileDownload/{id}/{md5}
summary: 下载文件的原图
operationId: GatewayControllerPart2_downloadFile
security: [{"api-key": []}, {"bearer": []}]
parameters:
  - id (in=path) required=True desc=文件ID schema={"type": "string"}
  - md5 (in=path) required=True desc=文件MD5值 schema={"type": "string"}
  - albumId (in=query) required=False desc=相册ID（可选） schema={"type": "number"}
  - auth_code (in=query) required=True desc=认证码 schema={"type": "string"}
response200: {"description": "返回文件内容"}

## GET /gateway/fileForApi/{id}/{md5}
summary: 显示文件的大图 - 已废弃
operationId: GatewayControllerPart2_renderFileForOpen
security: [{"api-key": []}, {"bearer": []}]
parameters:
  - id (in=path) required=True desc= schema={"type": "string"}
  - md5 (in=path) required=True desc= schema={"type": "string"}
  - api_key (in=query) required=True desc= schema={"type": "string"}
response200: {"description": "返回文件内容"}
