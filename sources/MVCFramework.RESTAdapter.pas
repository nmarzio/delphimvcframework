{ *******************************************************************************
  Copyright 2010-2015 Daniele Teti
  Copyright 2010-2015 Daniele Spinetti

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

  ******************************************************************************** }

unit MVCFramework.RESTAdapter;

interface

uses
  System.Rtti, System.TypInfo, MVCFramework.RESTClient, MVCFramework,
  IdIOHandler, System.Classes, System.SysUtils;

const
  URL_SEPARATOR = '/';

type

  RESTResourceAttribute = class(MVCHTTPMethodAttribute)
  private
    FURL: string;
    FHTTPMethodType: TMVCHTTPMethodType;
    procedure SetURL(const Value: string);
    procedure SetHTTPMethodType(const Value: TMVCHTTPMethodType);
  public
    constructor Create(AMVCHTTPMethod: TMVCHTTPMethodType; AURL: string);
    property URL: string read FURL write SetURL;
    property HTTPMethodType: TMVCHTTPMethodType read FHTTPMethodType write SetHTTPMethodType;
  end;

  BodyAttribute = class(TCustomAttribute)
  private
    FOwnsObject: boolean;
    procedure SetOwnsObject(const Value: boolean);
  public
    constructor Create(AOwnsObject: boolean = true);
    property OwnsObject: boolean read FOwnsObject write SetOwnsObject;
  end;

  ParamAttribute = class(TCustomAttribute)
  private
    FParamType: string;
    FCustomFormat: string;
    FParamMatch: string;
    procedure SetCustomFormat(const Value: string);
    procedure SetParamType(const Value: string);
    procedure SetParamMatch(const Value: string);
  public
    constructor Create(AParamMatch: string; AParamType: string = ''; ACustomFormat: string = '');
    property ParamMatch: string read FParamMatch write SetParamMatch;
    property ParamType: string read FParamType write SetParamType;
    property CustomFormat: string read FCustomFormat write SetCustomFormat;
    function FmtParamMatch: string;
  end;

  HeadersAttribute = class(TCustomAttribute)
  private
    FKey: string;
    FValue: string;
    procedure SetKey(const Value: string);
    procedure SetValue(const Value: string);
  public
    constructor Create(AKey: string; AValue: string);
    property Key: string read FKey write SetKey;
    property Value: string read FValue write SetValue;
  end;

  IRESTAdapter<T> = interface
    ['{AAA41F40-69DB-419B-9922-F59F990CBDB5}']
    function ResourcesService: T;
    procedure AddRequestHeaders(AObj: TRttiObject);
    procedure AddRequestHeader(AKey: string; AValue: string);
    procedure MapResult(AResp: IRESTResponse; AMethod: TRttiMethod; out AResult: TValue);
  end;

  TVIAdapter<T: IInvokable> = class(TVirtualInterface)
  protected
    procedure DoInvoke(Method: TRttiMethod; const Args: TArray<TValue>; out Result: TValue);
    procedure DoInvokeImpl(Method: TRttiMethod; const Args: TArray<TValue>; out Result: TValue); virtual; abstract;
  public
    constructor Create;
  end;

  TRESTAdapter<T: IInvokable> = class(TVIAdapter<T>, IRESTAdapter<T>)
  private
    FRESTClient: TRESTClient;
    procedure SetRESTClient(const Value: TRESTClient);
  protected
    procedure DoInvokeImpl(Method: TRttiMethod; const Args: TArray<TValue>; out Result: TValue); override;
    procedure AddRequestHeaders(AObj: TRttiObject);
    procedure AddRequestHeader(AKey: string; AValue: string);
    procedure MapResult(AResp: IRESTResponse; AMethod: TRttiMethod; out AResult: TValue);
    function GetURL(AMethod: TRttiMethod; const Args: TArray<TValue>): string;
    function GetBodyAsString(AMethod: TRttiMethod; const Args: TArray<TValue>): string;
  public
    constructor Create;
    destructor Destroy; override;
    function Build(ARESTClient: TRESTClient): T; overload;
    function Build(const AServerName: string; const AServerPort: Word = 80; AIOHandler: TIdIOHandler = nil): T; overload;

    function ResourcesService: T;
    property RESTClient: TRESTClient read FRESTClient write SetRESTClient;
  end;

  TAsynchRequest = class(TObject)
  private
    FSynchronized: boolean;
    FSuccessProc: TProc<IRESTResponse>;
    FErrorProc: TProc<Exception>;
    FAlwaysProc: TProc;
    procedure SetAlwaysProc(const Value: TProc);
    procedure SetErrorProc(const Value: TProc<Exception>);
    procedure SetSuccessProc(const Value: TProc<IRESTResponse>);
    procedure SetSynchronized(const Value: boolean);
  public
    constructor Create(AProc: TProc<IRESTResponse> = nil; AProcErr: TProc<Exception> = nil; AProcAlways: TProc = nil;
      ASynchronized: boolean = false);
    property SuccessProc: TProc<IRESTResponse> read FSuccessProc write SetSuccessProc;
    property ErrorProc: TProc<Exception> read FErrorProc write SetErrorProc;
    property AlwaysProc: TProc read FAlwaysProc write SetAlwaysProc;
    property Synchronized: boolean read FSynchronized write SetSynchronized;
  end;

implementation

uses
  ObjectsMappers,
{$IF CompilerVersion < 27}
  Data.DBXJSON,
  Data.SqlExpr,
  DBXCommon,
{$ELSE}
  System.JSON,
{$ENDIF}
  RTTIUtilsU, DuckListU,
  Generics.Collections;

{ TRESTAdapter }

function TRESTAdapter<T>.Build(ARESTClient: TRESTClient): T;
begin
  RESTClient := ARESTClient;
  Result := ResourcesService;
end;

{ TVIAdapter }

constructor TVIAdapter<T>.Create;
begin
  inherited Create(TypeInfo(T), DoInvoke);
end;

procedure TVIAdapter<T>.DoInvoke(Method: TRttiMethod; const Args: TArray<TValue>; out Result: TValue);
begin
  DoInvokeImpl(Method, Args, Result);
end;

procedure TRESTAdapter<T>.AddRequestHeader(AKey, AValue: string);
begin
  if CompareText(AKey, 'ContentType') = 0 then
    FRESTClient.ContentType(AValue)
  else if CompareText(AKey, 'ContentEncoding') = 0 then
    FRESTClient.ContentEncoding(AValue)
  else if CompareText(AKey, 'Accept') = 0 then
    FRESTClient.Accept(AValue)
  else
    FRESTClient.RequestHeaders.Values[AKey] := AValue;
end;

procedure TRESTAdapter<T>.AddRequestHeaders(AObj: TRttiObject);
var
  _attr: TCustomAttribute;
begin
  for _attr in AObj.GetAttributes do
    if _attr is HeadersAttribute then
      AddRequestHeader(HeadersAttribute(_attr).Key, HeadersAttribute(_attr).Value);
end;

function TRESTAdapter<T>.Build(const AServerName: string; const AServerPort: Word; AIOHandler: TIdIOHandler): T;
var
  ARESTClient: TRESTClient;
begin
  ARESTClient := TRESTClient.Create(AServerName, AServerPort, AIOHandler);
  Result := Build(ARESTClient);
end;

constructor TRESTAdapter<T>.Create;
begin
  inherited Create;
end;

destructor TRESTAdapter<T>.Destroy;
begin
  if Assigned(FRESTClient) then
    FRESTClient.Free;
  inherited;
end;

procedure TRESTAdapter<T>.DoInvokeImpl(Method: TRttiMethod; const Args: TArray<TValue>; out Result: TValue);
var
  Resp: IRESTResponse;
  _restresourceattr: RESTResourceAttribute;
  URL: string;
  Body: string;
  AsynchClass: TAsynchRequest;
begin
  // Implementation of RESTClient DoGet DoPut ecc...
  if not TRTTIUtils.HasAttribute<RESTResourceAttribute>(Method, _restresourceattr) then
    raise Exception.CreateFmt('No REST Resource specified in method %s', [Method.Name]);

  // headers can be more than one
  FRESTClient.RequestHeaders.Clear;
  // Interface
  AddRequestHeaders(TRTTIUtils.ctx.GetType(TypeInfo(T)));
  // Method
  AddRequestHeaders(Method);

  // URL and Body
  URL := GetURL(Method, Args);
  Body := GetBodyAsString(Method, Args);

  // Asynch way to do
  if Args[Length(Args) - 1].TryAsType<TAsynchRequest>(AsynchClass) then
    FRESTClient.Asynch(
      procedure(ARESTResponse: IRESTResponse)
      var
        ResValue: TValue;
      begin
        MapResult(ARESTResponse, Method, ResValue);
        // AsynchClass.SuccessProc(ResValue.AsType<T>);
      end, AsynchClass.ErrorProc, AsynchClass.FAlwaysProc, AsynchClass.Synchronized);

  case _restresourceattr.HTTPMethodType of
    httpGET:
      Resp := FRESTClient.doGET(URL, []);
    httpPUT:
      Resp := FRESTClient.doPUT(URL, [], Body);
    httpPOST:
      Resp := FRESTClient.doPOST(URL, [], Body);
  end;

  // if the response code is > 400 raise exception
  // if Resp.ResponseCode >= 400 then
  // raise Exception.CreateFmt
  // ('Error on execute request ''%s''. Message: %d %s ',
  // [URL, Resp.ResponseCode, Resp.BodyAsString]);

  // if is a procedure no need a return type
  if Assigned(Method.ReturnType) then
    MapResult(Resp, Method, Result);

end;

function TRESTAdapter<T>.GetBodyAsString(AMethod: TRttiMethod; const Args: TArray<TValue>): string;
var
  _parameters: TArray<TRttiParameter>;
  I: Integer;
  _parameter: TRttiParameter;
  _param: BodyAttribute;
  Arg: TValue;
begin
  _parameters := AMethod.GetParameters;
  for I := 0 to Length(_parameters) - 1 do
  begin
    _parameter := _parameters[I];
    // ARG := ARGS[I+1] because
    // Args	RTTI for the arguments of the interface method that has been called. The first argument (located at index 0) represents the interface instance itself.
    Arg := Args[I + 1];
    if TRTTIUtils.HasAttribute<BodyAttribute>(_parameter, _param) then
      try
        if Arg.IsObject then
          Exit(Mapper.ObjectToJSONObjectString(Arg.AsObject))
        else
          Exit(TRTTIUtils.TValueAsString(Arg, '', ''));
      finally
        if _param.OwnsObject and Arg.IsObject then
          Arg.AsObject.Free;
      end;
  end;
end;

function TRESTAdapter<T>.GetURL(AMethod: TRttiMethod; const Args: TArray<TValue>): string;
var
  _restresourceattr: RESTResourceAttribute;
  IURL: string;
  SplitUrl: TArray<string>;
  URLDict: TDictionary<string, string>;
  Split: string;
  _parameters: TArray<TRttiParameter>;
  I: Integer;
  _parameter: TRttiParameter;
  _param: ParamAttribute;
  Arg: TValue;
begin
  _restresourceattr := TRTTIUtils.GetAttribute<RESTResourceAttribute>(AMethod);
  IURL := _restresourceattr.URL;
  SplitUrl := IURL.Split([URL_SEPARATOR]);
  URLDict := TDictionary<string, string>.Create;
  try
    for Split in SplitUrl do
      if not Split.IsEmpty then
        URLDict.Add(Split, Split);
    _parameters := AMethod.GetParameters;
    // ARG := ARGS[I+1] because
    // Args	RTTI for the arguments of the interface method that has been called. The first argument (located at index 0) represents the interface instance itself.
    for I := 0 to Length(_parameters) - 1 do
    begin
      _parameter := _parameters[I];
      Arg := Args[I + 1];
      if TRTTIUtils.HasAttribute<ParamAttribute>(_parameter, _param) then
        URLDict[_param.FmtParamMatch] := TRTTIUtils.TValueAsString(Arg, _param.ParamType, _param.CustomFormat);
    end;

    for Split in SplitUrl do
      if not Split.IsEmpty then
        Result := Result + URL_SEPARATOR + URLDict[Split];

    if IURL.EndsWith(URL_SEPARATOR) and not (Result.EndsWith(URL_SEPARATOR)) then
      Result := Result + URL_SEPARATOR;

  finally
    URLDict.Free;
  end;
end;

procedure TRESTAdapter<T>.MapResult(AResp: IRESTResponse; AMethod: TRttiMethod; out AResult: TValue);
var
  _attrlistof: MapperListOf;
begin
  if AMethod.ReturnType.TypeKind = tkClass then
  begin
    // ListOf
    if TRTTIUtils.HasAttribute<MapperListOf>(AMethod, _attrlistof) then
    begin
      AResult := TRTTIUtils.CreateObject(AMethod.ReturnType.QualifiedName);
      Mapper.JSONArrayToObjectList(WrapAsList(AResult.AsObject), _attrlistof.Value, AResp.BodyAsJsonValue as TJSONArray, false);
    end
    // JSONValue
    else if AMethod.ReturnType.AsInstance.MetaclassType.InheritsFrom(TJSONValue) then
      AResult := TJSONObject.ParseJSONValue(AResp.BodyAsString)
      // Object
    else
      AResult := Mapper.JSONObjectToObject(AMethod.ReturnType.QualifiedName, AResp.BodyAsJsonObject)
  end
  else
    // IRESTResponse
    if AMethod.ReturnType.QualifiedName = TRTTIUtils.ctx.GetType(TypeInfo(IRESTResponse)).QualifiedName then
      AResult := AResult.From(AResp)
    else // else a simple BodyAsString
      AResult := AResp.BodyAsString
end;

function TRESTAdapter<T>.ResourcesService: T;
var
  pInfo: PTypeInfo;
begin
  pInfo := TypeInfo(T);
  if QueryInterface(GetTypeData(pInfo).Guid, Result) <> 0 then
  begin
    raise Exception.CreateFmt('RESTAdapter is unable to cast %s to its interface', [string(pInfo.Name)]);
  end;
end;

procedure TRESTAdapter<T>.SetRESTClient(const Value: TRESTClient);
begin
  FRESTClient := Value;
end;

{ RESTResourceAttribute }

constructor RESTResourceAttribute.Create(AMVCHTTPMethod: TMVCHTTPMethodType; AURL: string);
begin
  FURL := AURL;
  FHTTPMethodType := AMVCHTTPMethod;
end;

procedure RESTResourceAttribute.SetHTTPMethodType(const Value: TMVCHTTPMethodType);
begin
  FHTTPMethodType := Value;
end;

procedure RESTResourceAttribute.SetURL(const Value: string);
begin
  FURL := Value;
end;

{ BodyAttribute }

constructor BodyAttribute.Create(AOwnsObject: boolean);
begin
  inherited Create;
  FOwnsObject := AOwnsObject;
end;

procedure BodyAttribute.SetOwnsObject(const Value: boolean);
begin
  FOwnsObject := Value;
end;

{ ParamAttribute }

constructor ParamAttribute.Create(AParamMatch: string; AParamType, ACustomFormat: string);
begin
  inherited Create;
  FParamMatch := AParamMatch;
  FParamType := AParamType;
  FCustomFormat := ACustomFormat;
end;

function ParamAttribute.FmtParamMatch: string;
begin
  Result := '{' + ParamMatch + '}';
end;

procedure ParamAttribute.SetCustomFormat(const Value: string);
begin
  FCustomFormat := Value;
end;

procedure ParamAttribute.SetParamMatch(const Value: string);
begin
  FParamMatch := Value;
end;

procedure ParamAttribute.SetParamType(const Value: string);
begin
  FParamType := Value;
end;

{ HeadersAttribute }

constructor HeadersAttribute.Create(AKey: string; AValue: string);
begin
  FKey := AKey;
  FValue := AValue;
end;

procedure HeadersAttribute.SetKey(const Value: string);
begin
  FKey := Value;
end;

procedure HeadersAttribute.SetValue(const Value: string);
begin
  FValue := Value;
end;

{ TAsynchRequest }

constructor TAsynchRequest.Create(AProc: TProc<IRESTResponse> = nil; AProcErr: TProc<Exception> = nil; AProcAlways: TProc = nil;
ASynchronized: boolean = false);
begin
  inherited Create;
  FSuccessProc := AProc;
  FErrorProc := AProcErr;
  FAlwaysProc := AProcAlways;
  FSynchronized := ASynchronized;
end;

procedure TAsynchRequest.SetAlwaysProc(const Value: TProc);
begin
  FAlwaysProc := Value;
end;

procedure TAsynchRequest.SetErrorProc(const Value: TProc<Exception>);
begin
  FErrorProc := Value;
end;

procedure TAsynchRequest.SetSuccessProc(const Value: TProc<IRESTResponse>);
begin
  FSuccessProc := Value;
end;

procedure TAsynchRequest.SetSynchronized(const Value: boolean);
begin
  FSynchronized := Value;
end;

end.