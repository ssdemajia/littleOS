org 0x7c00 ;设置起始地址

BaseOfStack equ 0x7c00
BaseOfLoader equ 0x1000
OffsetOfLoader equ 0x00

RootDirSectors equ 14 ;根目录所占扇区数
SectorNumOfRootDirStart equ 19 ;根目录起始扇区号
SectorNumOfFAT1Start equ 1 ; FAT表1的起始扇区号
SectorBalance equ 17 ; 1+9+9-2之所以减2是因为起始簇号是从2开始

    jmp short LabelStart
    nop
    BS_OEMName  db 'SSdeBoot'
    BPB_BytesPerSec dw 512
    BPB_SecPerClus db 1
    BPB_RsvdSecCount dw 1
    BPB_NumFATs db 2
    BPB_RootEntCount dw 224 ;目录项个数
    BPB_TotalSection16 dw 2880
    BPB_Media db 0f0h
    BPB_FATSz16 dw 9 ;每个FAT表所占扇区个数
    BPB_SecPerTrk dw 18; 每个磁道扇区数
    BPB_NumHeads dw 2
    BPB_HiddSec dd 0
    BPB_TotalSec32 dd 0
    BS_DriveNum db 0 ;int 13h 使用的驱动号
    BS_Reserved1 db 0
    BS_BootSig db 29h
    BS_VolID dd 0
    BS_VolLabel db 'boot loader'
    BS_FileSysType db 'FAT12   '

LabelStart:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, BaseOfStack

;======== 清空屏幕，使用bios的中断程序10的功能编号6
    mov ax, 0600h ;al为0,表示清空屏幕
    mov bx, 0700h
    mov cx, 0
    mov dx, 0184fh
    int 10h

;======== 设置光标，使用中断程序10的功能编号2
    mov ax, 0200h
    mov bx, 0000h
    mov dx, 0000h
    int 10h

;======== display 
    mov ax, 1301h
    mov bx, 000fh
    mov cx, 10
    push ax
    mov ax, ds
    mov es, ax
    pop ax
    mov bp, StartBootMessage
    int 10h

;======= reset floppy
    xor ah, ah
    xor dl, dl
    int 13h


;==== 在根目录搜索loader.bin
    mov word [SectorNo], SectorNumOfRootDirStart ;保存根目录起始扇区号 1 + 9 + 9
LabelSearchInRootDirBegin:
    cmp word [RootDirSizeForLoop], 0 ;需要遍历的目录项数量
    jz LabelNoLoaderBin
    dec word [RootDirSizeForLoop] ;
    mov ax, 00h;
    mov es, ax;
    mov bx, 8000h;es bx存放缓冲数据
    mov ax, [SectorNo] ;目录项的起始扇区编号
    mov cl, 1
    call FuncReadOneSector ;读取的数据在es bx
    mov si, LoaderFileName
    mov di, 8000h
    cld ;清空df标志位，因为df和之后用到的lodsb指令有关
    mov dx, 10h ;每个扇区存放16个目录项，512/32=16

LabelSearchForLoaderBin: ;遍历当前扇区的每一个目录项
    cmp dx, 0
    jz LabelGotoNextSectorInRootDir
    dec dx
    mov cx, 11

LabelCmpFilename: ;比较文件名
    cmp cx, 0
    jz LabelFileNameFound
    dec cx
    lodsb ;从[ds:si]寄存器中指定的地址读取到al中，si会自动增加，在ds:si中的是已经定义的loader文件名
    cmp al, byte [es:di] ;在缓存区读取的是es bx
    jz LabelGoOn 
    jmp LabelDifferent
    LabelGoOn:
        inc di
        jmp LabelCmpFilename
    LabelDifferent:
        and di, 0ffe0h ;65504 b1111111111100000
        add di, 20h
        mov si, LoaderFileName ;恢复指向文件名地址的si
        jmp LabelSearchForLoaderBin
    
LabelGotoNextSectorInRootDir:
    add word [SectorNo], 1
    jmp LabelSearchInRootDirBegin

LabelNoLoaderBin: ;没有找到目标loader.bin
    mov ax, 1301h
    mov bx, 008ch
    mov dx, 0100h
    mov cx, 22
    push ax
    mov ax, ds
    mov es, ax
    pop ax
    mov bp, NoLoaderMessage
    int 10h
    jmp $


;===发现目标文件
LabelFileNameFound:
    mov ax, RootDirSectors;根目录使用了14个扇区
    and di, 0ffe0h;将di初始化
    add di, 01ah;加上26，这个偏移是DIR_FstClus即起始簇号
    mov cx, word [es:di] ;读取起始簇号，两个字节（一个字）
    push cx
    add cx, ax
    add cx, SectorBalance
    mov ax, BaseOfLoader ;loader在内存中的地址放入es中
    mov es, ax
    mov bx, OffsetOfLoader;loader地址放入bx中
    mov ax, cx

LabelGoOnLoadingFile:
    push ax
    push bx
    mov ah, 0eh
    mov al, '.'
    mov bl, 0fh
    int 10h
    pop bx
    pop ax

    mov cl, 1
    call FuncReadOneSector
    pop ax ; Dir_FirstCluster
    call FuncGetFATEntry
    cmp ax, 0fffh ; 0fffh文件的最后一个簇
    jz LabelFileLoaded
    push ax
    mov dx, RootDirSectors ;此时ax中保持FAT表项的编号，第几个簇
    add ax, dx
    add ax, SectorBalance
    add bx, [BPB_BytesPerSec]
    jmp LabelGoOnLoadingFile


LabelFileLoaded: ;跳转至loader文件的位置
    jmp BaseOfLoader:OffsetOfLoader ;段间跳转，需要填入段地址


;=== 从软盘上读取一个扇区,ax是待读取的磁盘起始扇区号，cl为读入的扇区数量，ES:BX为目标缓冲区地址
FuncReadOneSector:
    push bp ;保存栈指针
    mov bp, sp  
    sub esp, 2
    mov byte [bp-2], cl ;保存cl
    push bx ; 保存bx
    mov bl, [BPB_SecPerTrk] ;每个磁道的扇区数
    div bl ;使用ax除以bl，也就是扇区号处以每个磁道扇区数，ah保存余数，al保存商
    inc ah ;余数是扇区起始编号，商al的第一位是磁头号，2到8是磁道号
    mov cl, ah ;cl保存扇区编号
    mov dh, al ;磁头号
    and dh, 1 ;dh中保存磁头号
    shr al, 1 ;磁道号
    mov ch, al ;ch中保存磁道号
    pop bx ;恢复bx
    mov dl, [BS_DriveNum] ;dl中保存驱动器号
    LabelGoOnReading:
        mov ah, 2
        mov al, byte [bp-2] ;原来保存cl中需要读取的扇区数量
        int 13h
        jc LabelGoOnReading ;读完后会将cf标志位复位
        add esp, 2
        pop bp
        ret


;=== 获取FAT表项, 输入ax表示第几个Cluster，读取那一项中的值Cluster
FuncGetFATEntry:
    push es
    push bx
    push ax
    mov ax, 0
    mov es, ax
    pop ax ; Dir_FirstCluster
    mov byte [Odd], 0
    mov bx, 3
    mul bx
    mov bx, 2
    div bx  ; ax*3/2 == ax*1.5
    cmp dx, 0 ; dx中保存余数
    jz LabelEven 
    mov byte [Odd], 1
    LabelEven:
        xor dx, dx
        mov bx, [BPB_BytesPerSec]
        div bx ;因为得到的是FAT表项索引的字节位置，现在获取处于哪个扇区
        push dx ; ax/bx=ax ax%bx=dx
        mov bx, 8000h ;0x08000的地址存放读取到的FAT表
        add ax, SectorNumOfFAT1Start ;FAT表1的起始扇区号
        mov cl, 2
        call FuncReadOneSector ;读取两个扇区到es：bx中
        pop dx
        add bx, dx 
        mov ax, [es:bx]
        cmp byte [Odd], 1
        jnz LabelOdd
        shr ax, 4
    LabelOdd:
        and ax, 0fffh
        pop bx
        pop es
        ret

;=== 临时变量
RootDirSizeForLoop dw RootDirSectors
SectorNo dw 0
Odd db 0

;=== Messages
StartBootMessage: db "Start Boot"
NoLoaderMessage: db "Error: No Loader Found"
LoaderFileName: db "LOADER  BIN"
times 510 - ($ - $$) db 0
dw 0xaa55