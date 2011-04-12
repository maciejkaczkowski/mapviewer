{ Thread Pool

  Copyright (C) 2011 Maciej Kaczkowski / keit.co

  This library is free software; you can redistribute it and/or modify it
  under the terms of the GNU Library General Public License as published by
  the Free Software Foundation; either version 2 of the License, or (at your
  option) any later version.

  This program is distributed in the hope that it will be useful, but WITHOUT
  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE. See the GNU Library General Public License
  for more details.

  You should have received a copy of the GNU Library General Public License
  along with this library; if not, write to the Free Software Foundation,
  Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
}
unit kcThreadPool;

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Classes, SysUtils, syncobjs;

type

  TParallelProc = procedure of object;
  TThreadPool = class;

  { TJob }

  TJob = class
  private
    FParallelProc: TParallelProc;
    FOwner: TThreadPool;
    FName: string;
  public
    procedure Execute; virtual;
    property ParallelProc: TParallelProc read FParallelProc write FParallelProc;
    property Owner: TThreadPool read FOwner write FOwner;
    property Name: string read FName write FName;
  end;

  { TCustomThread }

  TCustomThread = class(TThread)
  private
    FJobName: string;
    FOwner: TThreadPool;
    FRunning: Boolean;
  public
    procedure Execute; override;
    constructor Create(AOwner: TThreadPool);
    destructor Destroy; override;
    property Running: Boolean read FRunning;
    property JobName: string read FJobName write FJobName;
  end;

  { TThreadPool }

  TThreadPool = class
  private
    FPool: TStrings;
    FList: TStrings;
    FCS: TCriticalSection;
    FRunning: Boolean;
    function GetJob: TJob;
    function GetJobCount(Index: string): Integer;
    function GetJobExists(Index: string): Boolean;
    function GetJobsCount: Integer;
    procedure SetRunning(const AValue: Boolean);
    function GetRunningThreads: Integer;
  public
    class procedure Init;
    constructor Create(FThreads: Integer = 5);
    destructor Destroy; override;
    procedure Add(AJob: TParallelProc; AName: string = ''); overload;
    procedure Add(AJob: TJob); overload;
    procedure Execute;
    procedure Terminate;
    property Running: Boolean read FRunning write SetRunning;
    property CriticalSection: TCriticalSection read FCS;
    property JobCount[Index: string]: Integer read GetJobCount;
    property JobExists[Index: string]: Boolean read GetJobExists;
    property JobsCount: Integer read GetJobsCount;
  end;

var
  ThreadPool: TThreadPool;

implementation

{ TJob }

procedure TJob.Execute;
begin
  if Assigned(FParallelProc) then
    FParallelProc;
end;

{ TThreadPool }

function TThreadPool.GetJob: TJob;
begin
  FCS.Enter;
  try
    if FList.Count > 0 then
    begin
      Result := TJob(FList.Objects[0]);
      FList.Delete(0);
    end
    else
      Result := nil;
  finally
    FCS.Leave;
  end;
end;

function TThreadPool.GetJobCount(Index: string): Integer;
var
  i: Integer;
begin
  FCS.Enter;
  try
    Result := 0;
    for i := 0 to FList.Count - 1 do
      if Index = FList[i] then
        Result := Result + 1;
  finally
    FCS.Leave;
  end;
end;

function TThreadPool.GetJobExists(Index: string): Boolean;
var
  i: Integer;
begin
  FCS.Enter;
  try
    Result := False;

    if not Result then
    begin
      for i := 0 to FPool.Count - 1 do
      begin
        if Index = TCustomThread(FPool.Objects[i]).JobName then
        begin
          Result := True;
          Break;
        end;
      end;
    end;

    if not Result then
    begin
      for i := 0 to FList.Count - 1 do
      begin
        if Index = FList[i] then
        begin
          Result := True;
          Break;
        end;
      end;
    end;
  finally
    FCS.Leave;
  end;
end;

function TThreadPool.GetJobsCount: Integer;
begin
  Result := FList.Count;
end;

procedure TThreadPool.SetRunning(const AValue: Boolean);
var
  i: Integer;
begin
  FRunning := AValue;
  {$ifndef unix}
  for i := 0 to FPool.Count - 1 do
  begin
    if AValue then
      TCustomThread(FPool.Objects[i]).Resume
    else
      TCustomThread(FPool.Objects[i]).Suspend;
  end;
  {$endif unix}
end;

function TThreadPool.GetRunningThreads: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to FPool.Count - 1 do
    if TCustomThread(FPool.Objects[i]).Running then
      Inc(Result)
end;

class procedure TThreadPool.Init;
begin
  if not Assigned(ThreadPool) then
    ThreadPool := TThreadPool.Create;
end;

constructor TThreadPool.Create(FThreads: Integer = 5);
var
  i: Integer;
begin
  FPool := TStringList.Create;
  FCS := TCriticalSection.Create;
  FList := TStringList.Create;

  FCS.Enter;
  try
    for i := 1 to FThreads do
      FPool.AddObject('', TCustomThread.Create(Self));
  finally
    FCS.Leave;
  end;
end;

destructor TThreadPool.Destroy;
var
  i: Integer;
  c: TCustomThread;
  o: TObject;
begin
  for i := 0 to FPool.Count - 1 do
  begin
    c := TCustomThread(FPool.Objects[i]);
    FPool.Objects[i] := nil;
    c.Terminate;
    c.Free;
  end;

  FPool.Free;

  for i := 0 to FList.Count - 1 do
  begin
    o := FList.Objects[i];
    if Assigned(o) then
      o.Free;
  end;

  FList.Free;
  FCS.Free;
  inherited Destroy;
end;

procedure TThreadPool.Add(AJob: TParallelProc; AName: string);
var
  j: TJob;
begin
  j := TJob.Create;
  j.ParallelProc := AJob;
  j.Owner := Self;
  j.Name := AName;
  FCS.Enter;
  try
    FList.AddObject(AName, j);
  finally
    FCS.Leave;
  end;
end;

procedure TThreadPool.Add(AJob: TJob);
begin
  AJob.Owner := Self;
  FCS.Enter;
  try
    FList.AddObject(AJob.Name, AJob);
  finally
    FCS.Leave;
  end;
end;

procedure TThreadPool.Execute;
begin
  Running := True;
  try
    while (FList.Count > 0) do
      Sleep(10);
    while GetRunningThreads > 0 do
      Sleep(10);
  finally
    Running := False;
  end;
end;

procedure TThreadPool.Terminate;
var
  i: Integer;
begin
  for i := 0 to FPool.Count - 1 do
    TCustomThread(FPool.Objects[i]).Terminate;
end;

{ TCustomThead }

procedure TCustomThread.Execute;
var
  j: TJob;
begin
  while not Terminated do
  begin
    if FOwner.Running then
    begin
      j := FOwner.GetJob;
      if Assigned(j) then
      begin
        FOwner.FCS.Enter;
        FJobName := j.Name;
        FRunning := True;
        FOwner.FCS.Leave;
        try
          j.Execute;
        finally
          FOwner.FCS.Enter;
          FJobName := '';
          FRunning := False;
          FOwner.FCS.Leave;
        end;
        j.Free;
      end
      else
        FRunning := False;
    end;
    Sleep(10);
  end;
end;

constructor TCustomThread.Create(AOwner: TThreadPool);
begin
  FOwner := AOwner;
  inherited Create(False);
end;

destructor TCustomThread.Destroy;
begin
  inherited Destroy;
end;

finalization
  if Assigned(ThreadPool) then
    ThreadPool.Free;
  
end.
