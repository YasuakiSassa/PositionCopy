/*
    PositionCopyServer is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    PositionCopyServer is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with PositionCopyServer.  If not, see <http://www.gnu.org/licenses/>.
*/

#property copyright "SASSA, Yasuaki"
#property link      "https://www.sassa-factory.net"
#property version   "0.02"
#property strict

//--- input parameters
input string shareName = "sassa-factory_PositionCopy";

#define size_t	uint
#define DWORD	uint
#define HANDLE	uint
#define PVOID	uint

#define FILE_FLAG_WRITE_THROUGH			0x80000000
#define FILE_FLAG_OVERLAPPED			0x40000000
#define FILE_FLAG_NO_BUFFERING			0x20000000
#define FILE_FLAG_RANDOM_ACCESS			0x10000000
#define FILE_FLAG_SEQUENTIAL_SCAN		0x08000000
#define FILE_FLAG_DELETE_ON_CLOSE		0x04000000
#define FILE_FLAG_BACKUP_SEMANTICS		0x02000000
#define FILE_FLAG_POSIX_SEMANTICS		0x01000000
#define FILE_FLAG_SESSION_AWARE			0x00800000
#define FILE_FLAG_OPEN_REPARSE_POINT	0x00200000
#define FILE_FLAG_OPEN_NO_RECALL		0x00100000
#define FILE_FLAG_FIRST_PIPE_INSTANCE	0x00080000

#define GENERIC_READ				0x80000000
#define GENERIC_WRITE				0x40000000
#define GENERIC_EXECUTE				0x20000000
#define GENERIC_ALL					0x10000000

#define CREATE_NEW					1
#define CREATE_ALWAYS				2
#define OPEN_EXISTING				3
#define OPEN_ALWAYS					4
#define TRUNCATE_EXISTING			5

// dwOpenMode	
#define PIPE_ACCESS_INBOUND         0x00000001
#define PIPE_ACCESS_OUTBOUND        0x00000002
#define PIPE_ACCESS_DUPLEX          0x00000003

// dwPipeMode
#define PIPE_WAIT                   0x00000000
#define PIPE_NOWAIT                 0x00000001
#define PIPE_READMODE_BYTE          0x00000000
#define PIPE_READMODE_MESSAGE       0x00000002
#define PIPE_TYPE_BYTE              0x00000000
#define PIPE_TYPE_MESSAGE           0x00000004
#define PIPE_ACCEPT_REMOTE_CLIENTS  0x00000000
#define PIPE_REJECT_REMOTE_CLIENTS  0x00000008

#define PIPE_UNLIMITED_INSTANCES    255

#define INFINITE					0xFFFFFFFF

#define WAIT_OBJECT_0				0

struct OVERLAPPED {
	uint Internal;
	uint InternalHigh;
	DWORD Offset;
	DWORD OffsetHigh;
	HANDLE hEvent;
};

#import "kernel32.dll"
	HANDLE CreateNamedPipeW( string lpName, DWORD dwOpenMode, DWORD dwPipeMode, DWORD nMaxInstances, DWORD nOutBufferSize, DWORD nInBufferSize, DWORD nDefaultTimeOut, PVOID lpSecurityAttributes );
	bool ConnectNamedPipe( HANDLE hNamedPipe, OVERLAPPED& lpOverlapped );
	bool DisconnectNamedPipe( HANDLE hNamedPipe );
	bool CloseHandle( HANDLE hObject );
	HANDLE CreateFileW( string lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode, PVOID lpSecurityAttributes, DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes, HANDLE hTemplateFile );
	bool ReadFile( HANDLE hFile, ushort& lpBuffer[], DWORD nNumberOfBytesToRead, DWORD& lpNumberOfBytesRead, PVOID lpOverlapped );
	bool WriteFile( HANDLE hFile, ushort& lpBuffer[], DWORD nNumberOfBytesToWrite, DWORD& lpNumberOfBytesWritten, PVOID lpOverlapped );
	HANDLE CreateEventW( PVOID lpEventAttributes, bool bManualReset, bool bInitialState, string lpName );
	DWORD WaitForMultipleObjects( DWORD nCount, HANDLE& lpHandles[], bool bWaitAll, DWORD dwMilliseconds );
	bool SetEvent( HANDLE hEvent );
	bool ResetEvent( HANDLE hEvent );
	DWORD WaitForSingleObject( HANDLE hHandle, DWORD dwMilliseconds );
#import

HANDLE pipe = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
	pipe = CreateNamedPipeW( "\\\\.\\pipe\\" + shareName, PIPE_ACCESS_OUTBOUND | FILE_FLAG_OVERLAPPED, PIPE_WAIT | PIPE_TYPE_BYTE, PIPE_UNLIMITED_INSTANCES, 512 * 1024, 512 * 1024, 1000, NULL );

	EventSetMillisecondTimer( 100 );
   
	return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
	EventKillTimer();

	CloseHandle( pipe );
   
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
}

/**
 * 口座状況を取得する.
 * 通貨,残高,クレジット,余剰証拠金の順で出力する
 */
string GetAccountInfo()
{
	string currency = AccountCurrency();
	double balance = AccountBalance();
	double credit = AccountCredit();
	double marginFree = AccountFreeMargin();
	
	return
		currency + "," +
		DoubleToString( balance ) + "," +
		DoubleToString( credit ) + "," +
		DoubleToString( marginFree ) + "\n";
}

/**
 * 指定されたIndexのポジション状況を取得する.
 * シンボル(6文字),チケット,時間(エポック秒),売り買い,オープン価格,SL,TPの順に出力する.
 */
string GetPosition( uint positionIndex )
{
	if( !OrderSelect( positionIndex, SELECT_BY_POS ) ) return "";
	int orderType = OrderType();
	if( orderType != OP_BUY && orderType != OP_SELL ) return "";
	
	int ticket = OrderTicket();
	string symbol = OrderSymbol();
	datetime time = OrderOpenTime();
	int direction = orderType == OP_BUY ? 1 : -1;
	double volume = OrderLots();
	double price = OrderOpenPrice();
	double stoploss = OrderStopLoss();
	double takeprofit = OrderTakeProfit();
	double contract = SymbolInfoDouble( symbol, SYMBOL_TRADE_CONTRACT_SIZE );
	
	return
		StringSubstr( symbol, 0, 6 ) + "," +
		IntegerToString( ticket ) + "," +
		IntegerToString( time ) + "," +
		IntegerToString( direction ) + "," +
		DoubleToString( volume ) + "," +
		DoubleToString( price ) + "," +
		DoubleToString( stoploss ) + "," +
		DoubleToString( takeprofit ) + "," + 
		DoubleToString( contract ) + "\n";
}


//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
	// Connectionがつながるまでのイベント
	HANDLE connectEvent = CreateEventW( NULL, false, false, NULL );
	OVERLAPPED overlapped;
	overlapped.Internal = 0;
	overlapped.InternalHigh = 0;
	overlapped.Offset = 0;
	overlapped.OffsetHigh = 0;
	overlapped.hEvent = connectEvent;

	// クライアントへの接続を待たずにコネクション
	ConnectNamedPipe( pipe, overlapped );

	// クライアントへ接続したときのみパイプに書き込む
	// 100ms待って帰ってこない場合は一旦止める 無制限に待つとDeinitの際に止まらなくなる
	if( WaitForSingleObject( connectEvent, 100 ) == WAIT_OBJECT_0 ){
		// 証拠金状況とポジション状況を取得する
		string message = GetAccountInfo();
		uint size = OrdersTotal();
		for( uint i=0; i<size; i++) message += GetPosition( i );
		message += "end";
		
		// WriteFileに送るために配列に変換する
		ushort szMessage[];
		ArrayResize( szMessage, StringLen( message ) + 1 );
		StringToShortArray( message, szMessage );
		
		// パイプに書き込む
		DWORD result;
		WriteFile( pipe, szMessage, ( StringLen( message ) + 1 ) * 2, result, NULL );
		ArrayFree( szMessage );
	}
	
	DisconnectNamedPipe( pipe );
	CloseHandle( connectEvent );
}
//+------------------------------------------------------------------+
