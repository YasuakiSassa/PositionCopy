/*
    PositionCopyClient is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    PositionCopyClient is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with PositionCopyClient.  If not, see <http://www.gnu.org/licenses/>.
*/
#property copyright "SASSA, Yasuaki"
#property link      "https://www.sassa-factory.net"
#property version   "0.02"

enum CopyType{
	fixed,
	oneness,
	balanceProp,
	marginProp,
	marginFreeProp
};

//--- input parameters
input long		magicNumber = 333;
input string	server = ".";
input string	shareName = "sassa-factory_PositionCopy";
input uint		syncTime = 100;
input CopyType	copyType = fixed;
input double	fixVolume = 0.01;
input double	proportional = 0.95;
input int		distance = 10;

#define size_t	ulong
#define DWORD	uint
#define HANDLE	ulong
#define PVOID	ulong

#define GENERIC_READ		0x80000000
#define GENERIC_WRITE		0x40000000
#define GENERIC_EXECUTE		0x20000000
#define GENERIC_ALL			0x10000000

#define CREATE_NEW			1
#define CREATE_ALWAYS		2
#define OPEN_EXISTING		3
#define OPEN_ALWAYS			4
#define TRUNCATE_EXISTING	5

#define INVALID_HANDLE_VALUE	-1

#import "kernel32.dll"
	bool CloseHandle( HANDLE hObject );
	HANDLE CreateFileW( string lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode, PVOID lpSecurityAttributes, DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes, HANDLE hTemplateFile );
	bool ReadFile( HANDLE hFile, ushort& lpBuffer[], DWORD nNumberOfBytesToRead, DWORD& lpNumberOfBytesRead, PVOID lpOverlapped );
	bool WriteFile( HANDLE hFile, ushort& lpBuffer[], DWORD nNumberOfBytesToWrite, DWORD& lpNumberOfBytesWritten, PVOID lpOverlapped );
#import

class AccountInfo {
public:
	AccountInfo( string currency_, double balance_, double credit_, double marginFree_ ) : 
		currency( currency_ ),
		balance( balance_ ),
		credit( credit_ ),
		margin( balance_ + credit_ ),
		marginFree( marginFree_ )
	{}
	
	const string currency;
	const double balance;
	const double credit;
	const double margin;
	const double marginFree;
};

class PositionInfo {
public:
	enum Direction {
		negative = -1,
		zero = 0,
		positive = 1
	};
	
	const string	symbol;
	const ulong		ticket;
	const datetime	time;
	const Direction	direction;
	const double	volume;
	const double	price;
	const double	stoploss;
	const double	takeprofit;
	const string	comment;
	const double	contract;

	virtual bool Order( AccountInfo* clientAccountInfo, AccountInfo* serverAccountInfo ) = 0;
	virtual bool Update( PositionInfo* position ) = 0;
	
protected:
	bool			same;

	PositionInfo( string symbol_, ulong ticket_, datetime time_, Direction direction_, double volume_, double price_, double stoploss_, double takeprofit_, string comment_, double contract_ ) :
		symbol( symbol_ ),
		ticket( ticket_ ),
		time( time_ ),
		direction( direction_ ),
		volume( volume_ ),
		price( price_ ),
		stoploss( stoploss_ ),
		takeprofit( takeprofit_ ),
		comment( comment_ ),
		contract( contract_ ),
		same( false )
	{}
	
};

class PositionServer : public PositionInfo {
public:
	PositionServer( string symbol_, ulong ticket_, datetime time_, int direction_, double volume_, double price_, double stoploss_, double takeprofit_, double contract_ ) :
		PositionInfo( symbol_, ticket_, time_, (Direction)direction_, volume_, price_, stoploss_, takeprofit_, "", contract_ )
	{}
	
	virtual bool Order( AccountInfo* clientAccountInfo, AccountInfo* serverAccountInfo ) {
		if( same || clientAccountInfo == NULL || serverAccountInfo == NULL ) return false;

		double tick = SymbolInfoDouble( symbol, SYMBOL_TRADE_TICK_SIZE );
		
		MqlTradeRequest request = { 0 };
		int diff = 0;
		if( direction == positive ) {
			request.type = ORDER_TYPE_BUY;
			request.price = SymbolInfoDouble( symbol, SYMBOL_ASK );
			diff = (int)( ( request.price - price ) / tick );
		} else if( direction == negative ) {
			request.type = ORDER_TYPE_SELL;
			request.price = SymbolInfoDouble( symbol, SYMBOL_BID );
			diff = (int)( ( price - request.price ) / tick );
		} else
			return false;
		if( diff > distance ) return false;
		request.volume = CalcVolume( clientAccountInfo, serverAccountInfo );
		if( request.volume == 0 ) return false;
		request.action = TRADE_ACTION_DEAL;
		request.symbol = symbol;
		request.magic = magicNumber;
		request.sl = stoploss;
		request.tp = takeprofit;
		request.comment = IntegerToString( ticket );
		request.magic = magicNumber;
		request.deviation = 100;
		request.type_filling = ORDER_FILLING_IOC;
		request.type_time = ORDER_TIME_GTC;
		
		MqlTradeResult result = { 0 };
		bool ret =  OrderSend( request, result );
		return ret;
	}
	
	virtual bool Update( PositionInfo* position ) {
		same = true;
		return true;
	}

private:

	double CalcVolume( AccountInfo* clientAccountInfo, AccountInfo* serverAccountInfo ) {
		double vol = 0;

		switch( copyType ){
			case fixed :
				vol = fixVolume;
				break;
			case oneness :
				vol = proportional * volume;
				break;
			case balanceProp :
				vol = proportional * volume * clientAccountInfo.balance / serverAccountInfo.balance;
				break;
			case marginProp :
				vol = proportional * volume * clientAccountInfo.margin / serverAccountInfo.margin;
				break;
			case marginFreeProp :
				vol = proportional * volume * clientAccountInfo.marginFree / serverAccountInfo.marginFree;
				break;
		}
		
		double minVolume = SymbolInfoDouble( symbol, SYMBOL_VOLUME_MIN );
		int lot = (int)( vol / minVolume );
		return lot * minVolume;
	}
};

class PositionClientPosition : public PositionInfo {
public:
	PositionClientPosition( string symbol_, ulong ticket_, datetime time_, ENUM_POSITION_TYPE type, double volume_, double price_, double stoploss_, double takeprofit_, string comment_ ) :
		PositionInfo( symbol_, ticket_, time_, type == POSITION_TYPE_BUY ? positive : negative, volume_, price_, stoploss_, takeprofit_, comment_, SymbolInfoDouble( symbol, SYMBOL_TRADE_CONTRACT_SIZE ) )
	{}

	virtual bool Order( AccountInfo* clientAccountInfo, AccountInfo* serverAccountInfo ) {
		if( same ) return false;
	
		MqlTradeRequest request = { 0 };
		if( direction == positive ) {
			request.type = ORDER_TYPE_SELL;
			request.price = SymbolInfoDouble( symbol, SYMBOL_BID );
		} else if( direction == negative ) {
			request.type = ORDER_TYPE_BUY;
			request.price = SymbolInfoDouble( symbol, SYMBOL_ASK );
		} else
			return false;
		request.action = TRADE_ACTION_DEAL;
		request.position = ticket;
		request.symbol = symbol;
		request.volume = volume;
		request.magic = magicNumber;
		request.deviation = 100;
		request.type_filling = ORDER_FILLING_IOC;
		request.type_time = ORDER_TIME_GTC;
		
		MqlTradeResult result = { 0 };
		bool ret =  OrderSend( request, result );
		return ret;
	}
	
	virtual bool Update( PositionInfo* position ) {
		same = true;
		
		if( position.stoploss == stoploss && position.takeprofit == takeprofit ) return true;
		
		MqlTradeRequest request = { 0 };
		request.action = TRADE_ACTION_SLTP;
		request.position = ticket;
		request.sl = position.stoploss;
		request.tp = position.takeprofit;
		
		MqlTradeResult result = { 0 };
		bool ret =  OrderSend( request, result );
		return ret;
	}
};

class PositionClientOrder : public PositionInfo {
public:
	PositionClientOrder( string symbol_, ulong ticket_, datetime time_, ENUM_ORDER_TYPE type, double volume_, double openPrice_, double stopLoss_, double takeProfit_, string comment_ ) :
		PositionInfo( symbol_, ticket_, time_, OrderTypeToDirection( type ), volume_, openPrice_, stopLoss_, takeProfit_, comment_, SymbolInfoDouble( symbol, SYMBOL_TRADE_CONTRACT_SIZE ) )
	{}
	
	virtual bool Order( AccountInfo* clientAccountInfo, AccountInfo* serverAccountInfo ) {
		if( same ) return false;
	
		MqlTradeRequest request = { 0 };
		request.action = TRADE_ACTION_REMOVE;
		request.magic = magicNumber;
		request.order = ticket;
		
		MqlTradeResult result = { 0 };
		bool ret =  OrderSend( request, result );
		return ret;
	}

	virtual bool Update( PositionInfo* position ) {
		same = true;
		return true;
	}
	
private:
	Direction OrderTypeToDirection( ENUM_ORDER_TYPE type ) {
		if( type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT ) return positive;
		else if( type == ORDER_TYPE_SELL || type == ORDER_TYPE_SELL_LIMIT ) return negative;
		else return zero;
	}
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
	EventSetMillisecondTimer( 100 );
   
	return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit( const int reason )
{
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{

}

string ReadNamedPipeServer()
{
	HANDLE pipe = CreateFileW( "\\\\" + server + "\\pipe\\" + shareName, GENERIC_READ, 0, NULL, OPEN_EXISTING, 0, 0 );
	if( pipe == INVALID_HANDLE_VALUE ) return NULL;
	
	DWORD result = 0;
	ushort buffer[256 * 1024];
	ReadFile( pipe, buffer, 256 * 1024 * 2, result, NULL );
	
	CloseHandle( pipe );
	
	return ShortArrayToString( buffer, 0 );
}

bool GetServerInfo( string serverInfo, AccountInfo*& accountInfo, PositionInfo*& positionInfo[] )
{
	// 改行で区切る
	string line[];
	int lineCount = StringSplit( serverInfo, StringGetCharacter( "\n", 0 ), line );
	if( lineCount == 0 ) return false;
	
	// 1行目はアカウント情報
	string column[];
	if( StringSplit( line[0], StringGetCharacter( ",", 0 ), column ) != 4 ) {
		ArrayFree( line );
		return false;
	}
	accountInfo = new AccountInfo( column[0], StringToDouble( column[1] ), StringToDouble( column[2] ), StringToDouble( column[3] ) );
	ArrayFree( column );
	
	// 2行目以降はポジション情報
	ArrayResize( positionInfo, lineCount - 2 );
	for( int i=1; i<lineCount-1; i++ ) {
		if( StringSplit( line[i], StringGetCharacter( ",", 0 ), column ) != 9 ) {
			ArrayFree( column );
			ArrayFree( positionInfo );
			ArrayFree( line );
			return false;
		}
		
		positionInfo[i-1] = new PositionServer(
			column[0],
			StringToInteger( column[1] ),
			(datetime)StringToInteger( column[2] ),
			StringToInteger( column[3] ),
			StringToDouble( column[4] ),
			StringToDouble( column[5] ),
			StringToDouble( column[6] ),
			StringToDouble( column[7] ),
			StringToDouble( column[8] ) );

		ArrayFree( column );
	}
	
	string endline = line[ lineCount - 1];
	ArrayFree( line );
	
	return endline == "end";
}

bool GetClientInfo( AccountInfo*& accountInfo, PositionInfo*& positionInfo[] )
{
	// 口座情報を取得する
	string currency = AccountInfoString( ACCOUNT_CURRENCY );
	double balance = AccountInfoDouble( ACCOUNT_BALANCE );
	double credit = AccountInfoDouble( ACCOUNT_CREDIT );
	double marginFree = AccountInfoDouble( ACCOUNT_MARGIN_FREE );
	accountInfo = new AccountInfo( currency, balance, credit, marginFree );
	
	// MagicNumber一致するポジションとオーダーの総数を取得する
	uint resultSize = 0;
	uint positionSize = PositionsTotal();
	for( uint i=0; i<positionSize; i++ ) {
		PositionSelectByTicket( PositionGetTicket( i ) );
		if( PositionGetInteger( POSITION_MAGIC ) == magicNumber ) resultSize++;
	}
	uint orderSize = OrdersTotal();
	for( uint i=0; i<orderSize; i++) {
		if( !OrderSelect( OrderGetTicket( i ) ) ) continue;
		// Orderの場合はBUYとSELL以外無視
		ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger( ORDER_TYPE );
		if( OrderGetInteger( ORDER_MAGIC ) == magicNumber && ( orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_SELL ) ) resultSize++;
	}
	ArrayResize( positionInfo, resultSize );
	
	// Positionを取得する
	uint index = 0;
	for( uint i=0; i<positionSize; i++ ) {
		ulong ticket = PositionGetTicket( i );
		PositionSelectByTicket( ticket );
		if( PositionGetInteger( POSITION_MAGIC ) == magicNumber ) {
			string symbol = PositionGetString( POSITION_SYMBOL );
			datetime time = (datetime)PositionGetInteger( POSITION_TIME );
			ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger( POSITION_TYPE );
			double volume = PositionGetDouble( POSITION_VOLUME );
			double openPrice = PositionGetDouble( POSITION_PRICE_OPEN );
			double stopLoss = PositionGetDouble( POSITION_SL );
			double takeProfit = PositionGetDouble( POSITION_TP );
			string comment = PositionGetString( POSITION_COMMENT );
			
			positionInfo[index++] = new PositionClientPosition( symbol, ticket, time, positionType, volume, openPrice, stopLoss, takeProfit, comment );
		}
	}
	
	// Orderを取得する
	for( uint i=0; i<orderSize; i++ ) {
		ulong ticket = OrderGetTicket( i );
		if( ! OrderSelect( ticket ) ) continue;
		ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger( ORDER_TYPE );
		if( OrderGetInteger( ORDER_MAGIC ) == magicNumber && ( orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_SELL ) ) {
			string symbol = OrderGetString( ORDER_SYMBOL );
			datetime time = (datetime)OrderGetInteger( ORDER_TIME_SETUP_MSC );
			double volume = OrderGetDouble( ORDER_VOLUME_CURRENT );
			double openPrice = OrderGetDouble( ORDER_PRICE_OPEN );
			double stopLoss = OrderGetDouble( ORDER_SL );
			double takeProfit = OrderGetDouble( ORDER_TP );
			string comment = OrderGetString( ORDER_COMMENT );
			
			positionInfo[index++] = new PositionClientOrder( symbol, ticket, time, orderType, volume, openPrice, stopLoss, takeProfit, comment );
		}
	}
	
	return true;
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
	// PositionCopyServerからServer側のアカウント情報とポジション状況を読み取る
	AccountInfo* serverAccountInfo;
	PositionInfo* serverPositionInfo[];
	if( !GetServerInfo( ReadNamedPipeServer(), serverAccountInfo, serverPositionInfo ) ) return;

	// Client側のアカウント情報とポジション状況を読み取る
	AccountInfo* clientAccountInfo;
	PositionInfo* clientPositionInfo[];
	if( !GetClientInfo( clientAccountInfo, clientPositionInfo ) ) return;
	
	// ポジション情報を突き合わせて、Server側, Client側両方にあるものを調べる
	// Client側のコメントにServer側のTicketが記載されている
	int serverSize = ArraySize( serverPositionInfo );
	int clientSize = ArraySize( clientPositionInfo );
	for( int i=0; i<serverSize; i++ ) for( int j=0; j<clientSize; j++ )
		if( serverPositionInfo[i].ticket == StringToInteger( clientPositionInfo[j].comment ) ){
			serverPositionInfo[i].Update( clientPositionInfo[j] );
			clientPositionInfo[j].Update( serverPositionInfo[i] );
		}
			
	// ポジョションを開く、または、閉じる
	for( int i=0; i<clientSize; i++ ) clientPositionInfo[i].Order( clientAccountInfo, serverAccountInfo );
	for( int i=0; i<serverSize; i++ ) serverPositionInfo[i].Order( clientAccountInfo, serverAccountInfo );
	
	// 後始末
	delete serverAccountInfo;
	for( int i=0; i<serverSize; i++ ) delete serverPositionInfo[i];
	ArrayFree( serverPositionInfo );
	delete clientAccountInfo;
	for( int i=0; i<clientSize; i++ ) delete clientPositionInfo[i];
	ArrayFree( clientPositionInfo );
}
//+------------------------------------------------------------------+
