;+
; NAME:
;       PC_READ_VAR
;
; PURPOSE:
;       Read var.dat, or other VAR files in any imaginable way!
;
;       Returns one or more fields from a snapshot (var) file generated by a
;       Pencil-Code run.  Works for one or all processors. Can select subsets
;       of the data. And pretty much do everything you could dream with a var
;       file
;
; CATEGORY:
;       Pencil Code, File I/O
;
; CALLING SEQUENCE:
;       PC_READ_VAR, object=object, t=t,                          $
;                    varfile=varfile, datadir=datadir, proc=proc, $
;                    /NOSTATS, /QUIET, /HELP
; KEYWORD PARAMETERS:
;    datadir: specify the root data directory. Default is './data'   [string]
;       proc: specify a processor to get the data from. Default: ALL [integer]
;    varfile: name for the var file, default: 'var.dat'              [string]
;       ivar: a number to optionally append to the end of the        [integer]
;             varfile name.
;
;          t: returns the time of the snapshot                       [precision(mx)]
;
;     object: optional structure in which to return all the above    [structure]
;             (or those vars specified in VARIABLES)
;  variables: array of variable name to return                       [string(*)]
;
;  /ADDITIONAL: Load all variables stored in the files, PLUS any additional
;               variables specified with the variables=[] option.
;     /MAGIC: call pc_magic_var to replace special variable names with their
;             functional equivalents
;
;   /TRIMXYZ: remove ghost points from the x,y,z arrays that are returned
;   /TRIMALL: remove ghost points from all returned variables and x,y,z arrays
;             - this is equivalent to wrapping each requested variable with
;                     pc_noghost(..., dim=dim)
;               pc_noghost will skip, i.e. do nothing to variables not
;               initially of size (dim.mx,dim.my,dim.mz)
;
;   /NOSTATS: don't print any summary statistics for the returned fields
;     /STATS: force printing of summary statistics even if quiet is set
;     /RUN2D: read a 2D-snapshot written only in a (x,y) or (x,z) plane
;     /QUIET: instruction not to print any 'helpful' information
;      /HELP: display this usage information, and exit
;
; EXAMPLES:
;       pc_read_var,obj=vars             ;; read all vars into VARS struct
;       pc_read_var,obj=vars,PROC=5      ;; read only from data/proc5
;       pc_read_var,obj=vars,variables=['ss']
;                                        ;; read entropy into vars.ss
;       pc_read_var,obj=vars,variables=['bb'],/MAGIC
;                                        ;; calculate vars.bb from aa
;       pc_read_var,obj=vars,variables=['bb'],/MAGIC,/ADDITIONAL
;                                        ;; get vars.bb, vars.uu, vars.aa, etc.
;       pc_read_var,obj=vars,variables=['bb'],/MAGIC, /TRIMALL
;                                        ;; vars.bb without ghost points
;
; MODIFICATION HISTORY:
;       $Id: pc_read_var.pro,v 1.47 2007-05-27 09:00:47 ajohan Exp $
;       Written by: Antony J Mee (A.J.Mee@ncl.ac.uk), 27th November 2002
;
;-
pro pc_read_var, t=t,                                             $
            object=object, varfile=varfile_, associate=associate, $
            variables=variables, tags=tags, magic=magic, bb=bb,   $
            trimxyz=trimxyz, trimall=trimall,                     $
            nameobject=nameobject,                                $
            dim=dim,param=param,                                  $
            ivar=ivar,                                            $
            datadir=datadir,proc=proc,ADDITIONAL=ADDITIONAL,      $
            nxrange=nxrange,nyrange=nyrange,nzrange=nzrange,      $
            STATS=STATS,NOSTATS=NOSTATS,QUIET=QUIET,HELP=HELP,    $
            SWAP_ENDIAN=SWAP_ENDIAN,varcontent=varcontent,        $
            scalar=scalar,run2D=run2D

COMPILE_OPT IDL2,HIDDEN
;
; Use common block belonging to derivative routines etc. so we can
; set them up properly.
;
  common cdat,x,y,z,mx,my,mz,nw,ntmax,date0,time0
  common cdat_nonequidist,dx_1,dy_1,dz_1,dx_tilde,dy_tilde,dz_tilde,lequidist
  common pc_precision, zero, one
;
; If no meaningful parameters are given show some help!
;
  IF ( keyword_set(HELP) ) THEN BEGIN
    doc_library,'pc_read_var'
    return
  ENDIF
;
; Default data directory
;
  IF (not keyword_set(datadir)) THEN datadir='data'
;
; Name and path of varfile to read
;
  if n_elements(ivar) eq 1 then begin
    default,varfile_,'VAR'
    varfile=varfile_+strcompress(string(ivar),/remove_all)
  endif else begin
    default,varfile_,'var.dat'
    varfile=varfile_
  endelse
;
; Get necessary dimensions QUIETly
;
  if (n_elements(dim) eq 0) then pc_read_dim,object=dim,datadir=datadir,proc=proc,/quiet
  if (n_elements(param) eq 0) then pc_read_param,object=param,dim=dim,datadir=datadir,/QUIET
;
; Call pc_read_grid to make sure any derivative stuff is correctly set in the common block
; Don't need the data fro anything though
;
  pc_read_grid,dim=dim,datadir=datadir,param=param,/QUIET,SWAP_ENDIAN=SWAP_ENDIAN
;
; Read problem dimensions (global)
;
  if (n_elements(proc) eq 1) then begin
    procdim=dim
  endif else begin
    pc_read_dim,object=procdim,datadir=datadir,proc=0,/QUIET
  endelse
;
; and check pc_precision is set for all Pencil Code tools
;
  pc_set_precision,dim=dim,quiet=quiet
;
; Should ghost zones be returned?
;
  if (keyword_set(TRIMALL)) then begin
    TRIMXYZ=1L
  endif else begin
    TRIMALL=0
  endelse
;
; Local shorthand for some parameters
;
  nx=dim.nx
  ny=dim.ny
  nz=dim.nz
  nw=dim.nx*dim.ny*dim.nz
  mx=dim.mx
  my=dim.my
  mz=dim.mz
  mvar=dim.mvar
  precision=dim.precision
  mxloc=procdim.mx
  myloc=procdim.my
  mzloc=procdim.mz
;
; Number of procs overwhich to loop
;
  if (n_elements(proc) eq 1) then nprocs=1 else nprocs = dim.nprocx*dim.nprocy*dim.nprocz
;
; Initialize / set default returns for ALL variables
;
  t=zero
  x=fltarr(mx)*one & y=fltarr(my)*one & z=fltarr(mz)*one
  dx=zero &  dy=zero &  dz=zero & deltay=zero

  if (n_elements(proc) ne 1) then begin
    xloc=fltarr(procdim.mx)*one & yloc=fltarr(procdim.my)*one & zloc=fltarr(procdim.mz)*one
  endif
;
;  Read meta data and set up variable/tag lists
;
  default,varcontent,pc_varcontent(datadir=datadir,dim=dim, $
                         param=param,quiet=quiet,scalar=scalar,run2D=run2D)
  totalvars=(size(varcontent))[1]-1L
;
  if n_elements(variables) ne 0 then begin
    VALIDATE_VARIABLES=1
    if keyword_set(ADDITIONAL) then begin
      filevars=(varcontent[where((varcontent[*].idlvar ne 'dummy'))].idlvar)[1:*]
      variables=[filevars,variables]
      if n_elements(tags) ne 0 then begin
        tags=[filevars,tags]
      endif
    endif
  endif else begin
    default,variables,(varcontent[where((varcontent[*].idlvar ne 'dummy'))].idlvar)[1:*]
  endelse
;
; Shortcut for getting magnetic field bb.
;
  if (bb) then begin
    variables=[variables,'bb']
    magic=1
  endif
;
  default,tags,variables
;
; Sanity check variables and tags
;
  if (n_elements(variables) ne n_elements(tags)) then begin
    message, 'ERROR: variables and tags arrays differ in size'
  endif
;
; Apply "magic" variable transformations for derived quantities
;
  if keyword_set(MAGIC) then pc_magic_var,variables,tags,param=param, $
      datadir=datadir
;
; Get a free unit number
;
  GET_LUN, file
;
; Prepare for read (build read command)
;
  res=''
  content=''
  for iv=1L,totalvars do begin
    if (n_elements(proc) eq 1) then begin
      res     = res + ',' + varcontent[iv].idlvar
    endif else begin
      res     = res + ',' + varcontent[iv].idlvarloc
    endelse
    content = content + ', ' + varcontent[iv].variable
;
; Initialise read buffers
;
    if (varcontent[iv].variable eq 'UNKNOWN') then $
             message, 'Unknown variable at position ' + str(iv)  $
                      + ' needs declaring in varcontent.pro', /INFO
    if (execute(varcontent[iv].idlvar+'='+varcontent[iv].idlinit,0) ne 1) then $
             message, 'Error initialising ' + varcontent[iv].variable $
                                      +' - '+ varcontent[iv].idlvar, /INFO
    if (n_elements(proc) ne 1) then begin
      if (execute(varcontent[iv].idlvarloc+'='+varcontent[iv].idlinitloc,0) ne 1) then $
               message, 'Error initialising ' + varcontent[iv].variable $
                                      +' - '+ varcontent[iv].idlvarloc, /INFO
    endif
;
; For vector quantities skip the required number of elements of the f array
;
    iv=iv+varcontent[iv].skip
  end
;
; Display information about the files contents
;
  content = strmid(content,2)
  IF ( not keyword_set(QUIET) ) THEN print,'File '+varfile+' contains: ', content
;
; Loop over processors
;
  for i=0,nprocs-1 do begin
    if (n_elements(proc) eq 1) then begin
      ; Build the full path and filename
      filename=datadir+'/proc'+str(proc)+'/'+varfile
    endif else begin
      filename=datadir+'/proc'+str(i)+'/'+varfile
      if (not keyword_set(QUIET)) then $
          print, 'Loading chunk ', strtrim(str(i+1)), ' of ', $
          strtrim(str(nprocs)), ' (', $
          strtrim(datadir+'/proc'+str(i)+'/'+varfile), ')...'
      pc_read_dim,object=procdim,datadir=datadir,proc=i,/QUIET
    endelse
    ; Check for existance and read the data
    dummy=findfile(filename, COUNT=countfile)
    if (not countfile gt 0) then begin
      message, 'ERROR: cannot find file '+ filename
    endif
;
; Setup the coordinates mappings from the processor
; to the full domain.
;
    if (n_elements(proc) eq 1) then begin
    endif else begin
;
;  Don't overwrite ghost zones of processor to the left (and
;  accordingly in y and z direction makes a difference on the
;  diagonals)
;
      if (procdim.ipx eq 0L) then begin
        i0x=0L
        i1x=i0x+procdim.mx-1L
        i0xloc=0L
        i1xloc=procdim.mx-1L
      endif else begin
        i0x=procdim.ipx*procdim.nx+procdim.nghostx
        i1x=i0x+procdim.mx-1L-procdim.nghostx
        i0xloc=procdim.nghostx & i1xloc=procdim.mx-1L
      endelse
;
      if (procdim.ipy eq 0L) then begin
        i0y=0L
        i1y=i0y+procdim.my-1L
        i0yloc=0L
        i1yloc=procdim.my-1L
      endif else begin
        i0y=procdim.ipy*procdim.ny+procdim.nghosty
        i1y=i0y+procdim.my-1L-procdim.nghosty
        i0yloc=procdim.nghosty
        i1yloc=procdim.my-1L
      endelse
;
      if (procdim.ipz eq 0L) then begin
        i0z=0L
        i1z=i0z+procdim.mz-1L
        i0zloc=0L
        i1zloc=procdim.mz-1L
      endif else begin
        i0z=procdim.ipz*procdim.nz+procdim.nghostz
        i1z=i0z+procdim.mz-1L-procdim.nghostz
        i0zloc=procdim.nghostz
        i1zloc=procdim.mz-1L
      endelse
;;
;; Skip this processor if it makes no contribution to the requested
;; subset of the domain.
;;
;       if (n_elements(nxrange)==2) then begin
;         if ((i0x gt nxrange[1]+procdim.nghostx) or (i1x lt nxrange[0]+procdim.nghostx)) then continue
;         ix0=max([ix0-(nxrange[0]+procdim.nghostx),0L]
;         ix1=min([ix1-(nxrange[0]+procdim.nghostx),ix0+(nxrange[1]-nxrange[0])]
;       endif
;       if (n_elements(nyrange)==2) then begin
;         if ((i0y gt nyrange[1]+procdim.nghosty) or (i1y lt nyrange[0]+procdim.nghosty)) then continue
;       endif
;       if (n_elements(nzrange)==2) then begin
;         if ((i0z gt nzrange[1]+procdim.nghostz) or (i1z lt nzrange[0]+procdim.nghostz)) then continue
;       endif
    endelse
;
; Open a varfile and read some data!
;
    close,file
    openr,file, filename, /F77,SWAP_ENDIAN=SWAP_ENDIAN
      if not keyword_set(ASSOCIATE) then begin
        if (execute('readu,file'+res) ne 1) then $
               message, 'Error reading: ' + 'readu,'+str(file)+res
      endif else begin
        message, 'ASSOCIATE BEHAVIOUR NOT IMPLEMENTED HERE YET'
      endelse
;
    if (n_elements(proc) eq 1) then begin
      if (param.lshear) then begin
        readu,file, t, x, y, z, dx, dy, dz, deltay
      endif else begin
        readu,file, t, x, y, z, dx, dy, dz
      endelse
    endif else begin
      if (param.lshear) then begin
        readu,file, t, xloc, yloc, zloc, dx, dy, dz, deltay
      endif else begin
        readu,file, t, xloc, yloc, zloc, dx, dy, dz
      endelse

      x[i0x:i1x] = xloc[i0xloc:i1xloc]
      y[i0y:i1y] = yloc[i0yloc:i1yloc]
      z[i0z:i1z] = zloc[i0zloc:i1zloc]

      for iv=1L,totalvars do begin
        if (varcontent[iv].variable eq 'UNKNOWN') then continue
  ;DEBUG: tmp=execute("print,'Minmax of "+varcontent[iv].variable+" = ',minmax("+varcontent[iv].idlvarloc+")")
        if (not keyword_set(run2D)) then begin
          ; classical 3D-run (x,y,z)
          cmd =   varcontent[iv].idlvar $
              + "[i0x:i1x,i0y:i1y,i0z:i1z,*,*]=" $
              + varcontent[iv].idlvarloc $
              +"[i0xloc:i1xloc,i0yloc:i1yloc,i0zloc:i1zloc,*,*]"
        endif else begin
          if (ny eq 1) then begin
            ; 2D-run in plane (x,z)
            cmd =   varcontent[iv].idlvar $
                + "[i0x:i1x,i0z:i1z,*,*]=" $
                + varcontent[iv].idlvarloc $
                +"[i0xloc:i1xloc,i0zloc:i1zloc,*,*]"
           endif else begin
             ; 2D-run in plane (x,y)
             cmd =   varcontent[iv].idlvar $
                 + "[i0x:i1x,i0y:i1y,*,*]=" $
                 + varcontent[iv].idlvarloc $
                 +"[i0xloc:i1xloc,i0yloc:i1yloc,*,*]"
           endelse
        endelse
        if (execute(cmd) ne 1) then $
            message, 'Error combining data for ' + varcontent[iv].variable

        ; For vector quantities skip the required number of elements
        iv=iv+varcontent[iv].skip
      endfor

    endelse

    if not keyword_set(ASSOCIATE) then begin
      close,file
      FREE_LUN,file
    endif
  endfor
;
; Tidy memory a little
;
  if (n_elements(proc) ne 1) then begin
    undefine,xloc
    undefine,yloc
    undefine,zloc

    for iv=1L,totalvars do begin
      undefine,varcontent[iv].idlvarloc
    endfor
  endif
;
;  ; Build structure of all the variables
;  ;if (n_elements(proc) eq 1) then begin
;  ;  objectname=filename+arraytostring(tags,LIST='_')
;  ;endif else begin
;  ;  objectname=datadir+varfile+arraytostring(tags,LIST='_')
;  ;endelse
;
;  ;makeobject="object = CREATE_STRUCT(name='"+objectname+"',['t','x','y','z','dx','dy','dz'" + $
;
  if keyword_set(VALIDATE_VARIABLES) then begin
    skipvariable=make_array(n_elements(variables),/INT,value=0)
    for iv=0,n_elements(variables)-1 do begin
    ;  res1=execute("testvariable=n_elements("+variables[iv]+")")
      res=execute(tags[iv]+'='+variables[iv])
      if not res then begin
        if not keyword_set(QUIET) then print,"% Skipping: "+tags[iv]+" -> "+variables[iv]
        skipvariable[iv]=1
      endif
    endfor
    testvariable=0
    if min(skipvariable) ne 0 then begin
      return
    endif
    if max(skipvariable) eq 1 then begin
      variables=variables[where(skipvariable eq 0)]
      tags=tags[where(skipvariable eq 0)]
    endif
  endif
;
; Save changs to the variables array (but don't include the effect of /TRIMALL)
;
  variables_in=variables
;
; Trim x, y and z if requested
;
  if (keyword_set(TRIMXYZ)) then begin
    xyzstring="x[dim.l1:dim.l2],y[dim.m1:dim.m2],z[dim.n1:dim.n2]"
  endif else begin
    xyzstring="x,y,z"
  endelse

  if keyword_set(TRIMALL) then begin
  ;  if not keyword_set(QUIET) then print,'NOTE: TRIMALL assumes the result of all specified variables has dimensions from the varfile (with ghosts)'
    variables = 'pc_noghost('+variables+',dim=dim,run2D=run2D)'
  endif
;
  makeobject = "object = "+ $
      "CREATE_STRUCT(name=objectname,['t','x','y','z','dx','dy','dz'" + $
      arraytostring(tags,QUOTE="'") + "],t,"+xyzstring+",dx,dy,dz" + $
      arraytostring(variables) + ")"
;
  if (execute(makeobject) ne 1) then begin
    message, 'ERROR Evaluating variables: '+makeobject
    undefine,object
  endif
;
; If requested print a summary (actually the default - unless being QUIET.)
;
  if keyword_set(STATS) or (not (keyword_set(NOSTATS) or keyword_set(QUIET))) then begin
    if not keyword_set(QUIET) then print,''
    if not keyword_set(QUIET) then print,'VARIABLE SUMMARY:'
    pc_object_stats, object, dim=dim, TRIM=TRIMALL, QUIET=QUIET
    print,' t = ', t
  endif
;
end
