
/* Date:   31-12-2016
   Author: Omer Anjum
   Description:
   RK integration 55-Point with reduced shared memory (RSM)
Comments: 
Date: Jan 10, 2017
Omer Anjum: Changed the 19-point RK integration Kernel to 55-Point integration Kernel without changing the requirements of shared memory and simultaneously reducing the global memory traffic. The technique applied to achieve this is "scattering". In addition RSM in file name stands for reduced shared memory. In this version requirement for SM has been tried to reduce by reusing the arrays defined in the shared memory. The memory could further be reduced. However, the code is breaking for some reason if it is reduced further and needs to be fixed. 
*/


//#include "hydro.cuh"
//#include "continuity.cuh"
#include "boundcond.cuh"
#include "dconstsextern.cuh"
#include "smem.cuh"
//#include "forcing.cuh"
//#include "shear.cuh"
//#include "diff.cuh"

//DEBUG
#include "diagnostics.cuh"


/*
* Notes:
* -diff functions are defined here, so that 
* these __device__ functions can be optimized
* by the compiler when compiling rungekutta_steps.
* This results in a very large speedup with the cost
* of larger source files.
*
* -__launch_bounds__(maximum threads per block, minimum number of blocks we want to multithread on SMs)
* tells the compiler how many registers we want to use: the compiler calculates the maximum amount of
* registers it can use in order not to hit the register cap when we want to have certain amount of 
* thread blocks running on the SM. F.ex. max number of registers per SM is 65536 and we have 128-sized
* thread blocks and want to multithread 8 blocks => max registers per thread = 65536 / (128*8) = 64
*
* -restrict keyword tells the compiler that only one pointer is used to reference a certain value.
* This enables the compiler to optimize some memory fetches to read-only cache and registers because
* restrict keyword tells that the value temporarily stored to faster memory is always up-to-date and
* is only modified with that specific pointer.
*
* -sid_column maps to threadIdx.x and sid_row maps to threadIdx.y. This is done because c++ arrays
* are row-major and nearby threads access a contiguous memory area (when computing der_scalx). 
* e.g. the shared memory block is arranged like s_scal[Y-direction][X-direction] where X and Y
* go to the same direction as X and Y in the device grids (d_lnrho etc.)
*
*Comments
*/



//------------------------------------------------------------------------------------------------------
//
// Derivative operators, 1st order 
//
__device__ float der_scalx(	int sid_row, int sid_column, 
				float s_scal[SHARED_SIZE_ROW][SHARED_SIZE_COL])
{
	//
	// Single derivative in x-direction
	//

	float res ;

	res = (
	-            s_scal[sid_row][sid_column-3] 
	+ d_FLT_9  * s_scal[sid_row][sid_column-2] 
	- d_FLT_45 * s_scal[sid_row][sid_column-1] 
	+ d_FLT_45 * s_scal[sid_row][sid_column+1] 
	- d_FLT_9  * s_scal[sid_row][sid_column+2] 
	+            s_scal[sid_row][sid_column+3] )
	* d_DIFF1_DX_DIV;
	// / ( d_FLT_60*d_DX ); 

	return res;
}


__device__ float der_scaly(	int sid_row, int sid_column, 
				float s_scal[SHARED_SIZE_ROW][SHARED_SIZE_COL])
{
   	//
   	// Single derivative in y-direction
	//

	float res ;

	res = (
	-            s_scal[sid_row-3][sid_column] 
	+ d_FLT_9  * s_scal[sid_row-2][sid_column] 
	- d_FLT_45 * s_scal[sid_row-1][sid_column] 
	+ d_FLT_45 * s_scal[sid_row+1][sid_column] 
	- d_FLT_9  * s_scal[sid_row+2][sid_column] 
	+            s_scal[sid_row+3][sid_column] )
	* d_DIFF1_DY_DIV;
	// / ( d_FLT_60*d_DY ); //MV: Made these divisions to go away. -> need only be calculated once and used as a constant. 

   return res;
}

__device__ float der_scalz(	float behind3, float behind2, float behind1,
				float infront1, float infront2, float infront3)
{
	//
	// Single derivative in z-direction
	//

	float res ;

	res = (
	-            behind3 
	+ d_FLT_9  * behind2
	- d_FLT_45 * behind1 
	+ d_FLT_45 * infront1 
	- d_FLT_9  * infront2 
	+            infront3 )
	* d_DIFF1_DZ_DIV;
	// / ( d_FLT_60*d_DZ );

	return res;
}
//------------------------------------------------------------------------------------------------------


//------------------------------------------------------------------------------------------------------
//
// Derivative operators, 2nd order 
//
__device__ float der2_scalx(int sid_row, int sid_column, float s_scal[SHARED_SIZE_ROW][SHARED_SIZE_COL])
{
	//
	// Double derivative in x-direction
	//
	float res;

	res = (
	  d_FLT_2   * s_scal[sid_row][sid_column-3]
	- d_FLT_27  * s_scal[sid_row][sid_column-2] 
	+ d_FLT_270 * s_scal[sid_row][sid_column-1] 
	- d_FLT_490 * s_scal[sid_row][sid_column  ]
	+ d_FLT_270 * s_scal[sid_row][sid_column+1]
	- d_FLT_27  * s_scal[sid_row][sid_column+2]
	+ d_FLT_2   * s_scal[sid_row][sid_column+3] )
	* d_DIFF2_DX_DIV;
	// / ( d_FLT_180*d_DX*d_DX );

	return res;

}

__device__ float der2_scaly(int sid_row, int sid_column, float s_scal[SHARED_SIZE_ROW][SHARED_SIZE_COL])
{
	//
	// Double derivative in y-direction
	//
	float res;

	res = (
	  d_FLT_2   * s_scal[sid_row-3][sid_column] 
	- d_FLT_27  * s_scal[sid_row-2][sid_column] 
	+ d_FLT_270 * s_scal[sid_row-1][sid_column] 
	- d_FLT_490 * s_scal[sid_row  ][sid_column] 
	+ d_FLT_270 * s_scal[sid_row+1][sid_column] 
	- d_FLT_27  * s_scal[sid_row+2][sid_column] 
	+ d_FLT_2   * s_scal[sid_row+3][sid_column] )
	* d_DIFF2_DY_DIV;
	// / ( d_FLT_180*d_DY*d_DY );

	return res;
}

__device__ float der2_scalz(int sid_row, int sid_column, float s_scal[SHARED_SIZE_ROW][SHARED_SIZE_COL],
				float behind3, float behind2, float behind1,
				float infront1, float infront2, float infront3)
{
	//
	// Double derivative in z-direction
	//
	float res;

	res = (
	  d_FLT_2   * behind3 
	- d_FLT_27  * behind2 
	+ d_FLT_270 * behind1 
	- d_FLT_490 * s_scal[sid_row][sid_column] 
	+ d_FLT_270 * infront1 
	- d_FLT_27  * infront2 
	+ d_FLT_2   * infront3 )
	* d_DIFF2_DZ_DIV;
	// / ( d_FLT_180*d_DY*d_DY );

	return res;

}

__device__ float der2_scalxy(int sid_row, int sid_column, float s_scal[SHARED_SIZE_ROW][SHARED_SIZE_COL])
{
	//
	// Double derivative in xy-direction
	//
	float res;

	res = (
	  d_FLT_2   * (s_scal[sid_row - 3][sid_column - 3]-s_scal[sid_row + 3][sid_column - 3]+s_scal[sid_row + 3][sid_column + 3]-s_scal[sid_row - 3][sid_column + 3])
	- d_FLT_27  * (s_scal[sid_row - 2][sid_column - 2]-s_scal[sid_row + 2][sid_column - 2]+s_scal[sid_row + 2][sid_column + 2]-s_scal[sid_row - 2][sid_column + 2])
	+ d_FLT_270 * (s_scal[sid_row - 1][sid_column - 1]-s_scal[sid_row + 1][sid_column - 1]+s_scal[sid_row + 1][sid_column + 1]-s_scal[sid_row - 1][sid_column + 1])
	)* d_DIFFMN_DXDY_DIV;
	// / ( d_FLT_180*d_DY*d_DY );
	return res;
}

__device__ float der2_scalxz(int sid_row, int sid_column, float s_scal[SHARED_SIZE_ROW][SHARED_SIZE_COL], float res[])
{
	//
	// Double derivative in xz-direction
	//
	res[0] =  d_DIFFMN_DXDZ_DIV*d_FLT_2 * (s_scal[sid_row ][sid_column + 3] - s_scal[sid_row ][sid_column - 3]);
	res[1] =  -d_DIFFMN_DXDZ_DIV*d_FLT_27 * (s_scal[sid_row ][sid_column + 2] - s_scal[sid_row ][sid_column - 2]);
	res[2] =  d_DIFFMN_DXDZ_DIV*d_FLT_270 * (s_scal[sid_row ][sid_column + 1] - s_scal[sid_row ][sid_column - 1]);
	return 0;
}
__device__ float der2_scalyz(int sid_row, int sid_column, float s_scal[SHARED_SIZE_ROW][SHARED_SIZE_COL], float res[])
{
	//
	// Double derivative in yz-direction
	//
	res[0] =  d_DIFFMN_DYDZ_DIV*d_FLT_2 * (s_scal[sid_row + 3][sid_column] - s_scal[sid_row - 3][sid_column]);
	res[1] =  -d_DIFFMN_DYDZ_DIV*d_FLT_27 * (s_scal[sid_row + 2][sid_column] - s_scal[sid_row - 2][sid_column]);
	res[2] =  d_DIFFMN_DYDZ_DIV*d_FLT_270 * (s_scal[sid_row + 1][sid_column] - s_scal[sid_row - 1][sid_column]);
	return 0;
}

//------------------------------------------------------------------------------------------------------


//Computes the first part of a runge kutta integration step
//(everything except the gradient of divergence) 
template <int step_number>
__global__ void 
__launch_bounds__(RK_THREADS_PER_BLOCK, 4)
rungekutta_step_first_half(const float* __restrict__ d_lnrho, const float* __restrict__ d_uu_x, const float* __restrict__ d_uu_y, const float* __restrict__ d_uu_z, 
                  		float* __restrict__ d_w_lnrho, float* __restrict__ d_w_uu_x, float* __restrict__ d_w_uu_y, float* __restrict__ d_w_uu_z,
				float* __restrict__ d_lnrho_dest, float* __restrict__ d_uu_x_dest, float* __restrict__ d_uu_y_dest, float* __restrict__ d_uu_z_dest)
{	
	float ALPHA, BETA;
	switch (step_number) {
		case 0:
			ALPHA = d_ALPHA1;
			BETA = d_BETA1;
			break;
		case 1:
			ALPHA = d_ALPHA2;
			BETA = d_BETA2;
			break;
		case 2:
			ALPHA = d_ALPHA3;
			BETA = d_BETA3;
			break;
	}

	__shared__ float SM[SHARED_SIZE_ROW][SHARED_SIZE_COL]; //SHARED_SIZE_COL (RK_THREADS_X + 2*BOUND_SIZE) = (32 + 2*3) = 38
	//__shared__ float s_uu_x [SHARED_SIZE_ROW][SHARED_SIZE_COL];
	__shared__ float s_uu_y [SHARED_SIZE_ROW][SHARED_SIZE_COL];
	__shared__ float s_uu_z [SHARED_SIZE_ROW][SHARED_SIZE_COL];

	float (*s_lnrho)[SHARED_SIZE_COL];
	float (*s_uu_x)[SHARED_SIZE_COL];

	float w_lnrho;
	float w_uu_x;
	float w_uu_y;
	float w_uu_z;	

	const int grid_idx_x = threadIdx.x + blockIdx.x*blockDim.x;
	const int grid_idx_y = threadIdx.y + blockIdx.y*blockDim.y;
	const int grid_idx_z = threadIdx.z + blockIdx.z*blockDim.z*RK_ELEMS_PER_THREAD_FIRST;

	const int sid_col = threadIdx.x + BOUND_SIZE; //Varies between (3, blockDim.x + 3) if BOUND_SIZE == 3
	const int sid_row = threadIdx.y + BOUND_SIZE; //Varies between (3, blockDim.y + 3)

	//Index in the partial result array (doesn't have boundary zones)
	int w_grid_idx = (grid_idx_x) +
			 (grid_idx_y)*d_W_GRID_Y_OFFSET +
			 (grid_idx_z)*d_W_GRID_Z_OFFSET;

	//Index in the final result array (offset to start from first index of
	//the computational domain)
	//int grid_idx = 	(grid_idx_x + d_CX_BOT) +
	//		(grid_idx_y + d_CY_BOT)*d_GRID_Y_OFFSET +
	//		(grid_idx_z + d_CZ_BOT)*d_GRID_Z_OFFSET;
	int grid_idx = 	(grid_idx_x + d_CX_BOT) +
			(grid_idx_y + d_CY_BOT)*d_GRID_Y_OFFSET +
			(grid_idx_z + 0)*d_GRID_Z_OFFSET; // Only in zplane we are in halo zone
	

	float current_lnrho  = d_lnrho[grid_idx];
	float current_uu_x  = d_uu_x[grid_idx];
	float current_uu_y  = d_uu_y[grid_idx];
	float current_uu_z  = d_uu_z[grid_idx];

	float infront1_lnrho = d_lnrho[grid_idx + 1*d_GRID_Z_OFFSET];
	float infront2_lnrho = d_lnrho[grid_idx + 2*d_GRID_Z_OFFSET];
	float infront3_lnrho = d_lnrho[grid_idx + 3*d_GRID_Z_OFFSET];

	float infront1_uu_x = d_uu_x[grid_idx + 1*d_GRID_Z_OFFSET];
	float infront2_uu_x = d_uu_x[grid_idx + 2*d_GRID_Z_OFFSET];
	float infront3_uu_x = d_uu_x[grid_idx + 3*d_GRID_Z_OFFSET];

	float infront1_uu_y = d_uu_y[grid_idx + 1*d_GRID_Z_OFFSET];
	float infront2_uu_y = d_uu_y[grid_idx + 2*d_GRID_Z_OFFSET];
	float infront3_uu_y = d_uu_y[grid_idx + 3*d_GRID_Z_OFFSET];

	float infront1_uu_z = d_uu_z[grid_idx + 1*d_GRID_Z_OFFSET];
	float infront2_uu_z = d_uu_z[grid_idx + 2*d_GRID_Z_OFFSET];
	float infront3_uu_z = d_uu_z[grid_idx + 3*d_GRID_Z_OFFSET];
	
	float behind3_lnrho  = 0;
	float behind2_lnrho  = 0;
	float behind1_lnrho  = 0;
	
	

	float behind3_uu_x  = 0;
	float behind2_uu_x  = 0;
	float behind1_uu_x  = 0;

	

	float behind3_uu_y  = 0;
	float behind2_uu_y  = 0;
	float behind1_uu_y  = 0;
	
	

	float behind3_uu_z  = 0;
	float behind2_uu_z  = 0;
	float behind1_uu_z  = 0;

	
	//---------------------------------------------------------
	const int output_array_size = (2*BOUND_SIZE) + 1;
	float div_z_partial_ux[output_array_size];
	float div_z_partial_uy[output_array_size];
	float div_z_partial_uz[output_array_size];
	float diagonal_result_xz_uuz[BOUND_SIZE];
	float diagonal_result_yz_uuz[BOUND_SIZE];
	float diagonal_result_xz_uux[BOUND_SIZE];
	float diagonal_result_yz_uuy[BOUND_SIZE];
	float mom_x[BOUND_SIZE+1];
	float mom_y[BOUND_SIZE+1];
	float mom_z[BOUND_SIZE+1];
	
	float d2x_uu_x, d2xy_uu_x, ddz_lnrho, ddz_uu_x, ddx_lnrho, ddx_uu_x, ddy_lnrho, ddy_uu_x, ddz_uu_z, ddx_uu_z, ddy_uu_z, d2z_uu_z;
	float d2xy_uu_y, d2y_uu_y, ddz_uu_y, ddx_uu_y, ddy_uu_y;
	float nu_const_uu_x;
	//const float div_uux;
	//const float div_uuy;
	//const float div_uuz;
	//const float d2x_uu_x;
	//const float d2xy_uu_y;
	//const float d2xy_uu_x;
	//const float d2y_uu_y;
	//const float d2z_uu_z;
	//---------------------------------------------------------
	div_z_partial_ux[6] = 0;
	div_z_partial_uy[6] = 0;
	div_z_partial_uz[6] = 0;
	//div_uux = div_uuy = div_uuz = d2x_uu_x = d2xy_uu_y = d2xy_uu_x = d2y_uu_y = d2z_uu_z = 0;   

	for(int zplane = -3 ; zplane < RK_ELEMS_PER_THREAD_FIRST + 3; zplane++) {

		switch (step_number) {
			case 0:
				w_lnrho = 0.0f;
				w_uu_x  = 0.0f;
				w_uu_y  = 0.0f;
				w_uu_z  = 0.0f;
				break;
			default:
				w_lnrho = d_w_lnrho[w_grid_idx];
				w_uu_x  = d_w_uu_x [w_grid_idx];
				w_uu_y  = d_w_uu_y [w_grid_idx];
				w_uu_z  = d_w_uu_z [w_grid_idx];
				break;
		}

		//Load the previous step to shared memory
			s_lnrho = SM;
			s_lnrho[sid_row][sid_col] = current_lnrho;
			//s_uu_x [sid_row][sid_col] = current_uu_x;
			s_uu_y [sid_row][sid_col] = current_uu_y;
			s_uu_z [sid_row][sid_col] = current_uu_z;
		
		//Load halos (not optimal)
			if (threadIdx.x < BOUND_SIZE) {
		
				//Load left
				s_lnrho[sid_row][sid_col-BOUND_SIZE] = d_lnrho[grid_idx - BOUND_SIZE]; // Omer: page 1 filling in halozones of shared memory
				//s_uu_x [sid_row][sid_col-BOUND_SIZE] = d_uu_x [grid_idx - BOUND_SIZE];
				s_uu_y [sid_row][sid_col-BOUND_SIZE] = d_uu_y [grid_idx - BOUND_SIZE];
				s_uu_z [sid_row][sid_col-BOUND_SIZE] = d_uu_z [grid_idx - BOUND_SIZE];

				//Load right
				s_lnrho[sid_row][sid_col+RK_THREADS_X] = d_lnrho[grid_idx+RK_THREADS_X];
				//s_uu_x [sid_row][sid_col+RK_THREADS_X] = d_uu_x [grid_idx+RK_THREADS_X];
				s_uu_y [sid_row][sid_col+RK_THREADS_X] = d_uu_y [grid_idx+RK_THREADS_X];
				s_uu_z [sid_row][sid_col+RK_THREADS_X] = d_uu_z [grid_idx+RK_THREADS_X];
			
			}
			if (threadIdx.y < BOUND_SIZE) {
				//Load down
				s_lnrho[sid_row-BOUND_SIZE][sid_col] = d_lnrho[grid_idx - BOUND_SIZE*d_GRID_Y_OFFSET];
				//s_uu_x [sid_row-BOUND_SIZE][sid_col] = d_uu_x [grid_idx - BOUND_SIZE*d_GRID_Y_OFFSET];
				s_uu_y [sid_row-BOUND_SIZE][sid_col] = d_uu_y [grid_idx - BOUND_SIZE*d_GRID_Y_OFFSET];
				s_uu_z [sid_row-BOUND_SIZE][sid_col] = d_uu_z [grid_idx - BOUND_SIZE*d_GRID_Y_OFFSET];

				//Load up
				s_lnrho[sid_row+RK_THREADS_Y][sid_col] = d_lnrho[grid_idx + RK_THREADS_Y*d_GRID_Y_OFFSET];
				//s_uu_x [sid_row+RK_THREADS_Y][sid_col] = d_uu_x [grid_idx + RK_THREADS_Y*d_GRID_Y_OFFSET];
				s_uu_y [sid_row+RK_THREADS_Y][sid_col] = d_uu_y [grid_idx + RK_THREADS_Y*d_GRID_Y_OFFSET];
				s_uu_z [sid_row+RK_THREADS_Y][sid_col] = d_uu_z [grid_idx + RK_THREADS_Y*d_GRID_Y_OFFSET];
			}
			if(threadIdx.x < BOUND_SIZE && threadIdx.y < BOUND_SIZE){
				//Load corners of size 3x3 of halo zones not loaded above in shared memory
				//Left Up
				s_lnrho[sid_row-BOUND_SIZE][sid_col-BOUND_SIZE] = d_lnrho[grid_idx - BOUND_SIZE - BOUND_SIZE*d_GRID_Y_OFFSET];
				//s_uu_x [sid_row-BOUND_SIZE][sid_col-BOUND_SIZE] = d_uu_x[grid_idx - BOUND_SIZE - BOUND_SIZE*d_GRID_Y_OFFSET];
				s_uu_y [sid_row-BOUND_SIZE][sid_col-BOUND_SIZE] = d_uu_y[grid_idx - BOUND_SIZE - BOUND_SIZE*d_GRID_Y_OFFSET];
				s_uu_z [sid_row-BOUND_SIZE][sid_col-BOUND_SIZE] = d_uu_z[grid_idx - BOUND_SIZE - BOUND_SIZE*d_GRID_Y_OFFSET];

				//Left Down
				s_lnrho[sid_row+RK_THREADS_Y][sid_col-BOUND_SIZE] = d_lnrho[grid_idx - BOUND_SIZE + RK_THREADS_Y*d_GRID_Y_OFFSET];
				//s_uu_x [sid_row+RK_THREADS_Y][sid_col-BOUND_SIZE] = d_uu_x[grid_idx - BOUND_SIZE + RK_THREADS_Y*d_GRID_Y_OFFSET];
				s_uu_y [sid_row+RK_THREADS_Y][sid_col-BOUND_SIZE] = d_uu_y[grid_idx - BOUND_SIZE + RK_THREADS_Y*d_GRID_Y_OFFSET];
				s_uu_z [sid_row+RK_THREADS_Y][sid_col-BOUND_SIZE] = d_uu_z[grid_idx - BOUND_SIZE + RK_THREADS_Y*d_GRID_Y_OFFSET];

				//Right Up
				s_lnrho[sid_row-BOUND_SIZE][sid_col+RK_THREADS_X] = d_lnrho[grid_idx + RK_THREADS_X - BOUND_SIZE*d_GRID_Y_OFFSET];
				//s_uu_x [sid_row-BOUND_SIZE][sid_col+RK_THREADS_X] = d_uu_x[grid_idx + RK_THREADS_X - BOUND_SIZE*d_GRID_Y_OFFSET];
				s_uu_y [sid_row-BOUND_SIZE][sid_col+RK_THREADS_X] = d_uu_y[grid_idx + RK_THREADS_X - BOUND_SIZE*d_GRID_Y_OFFSET];
				s_uu_z [sid_row-BOUND_SIZE][sid_col+RK_THREADS_X] = d_uu_z[grid_idx + RK_THREADS_X - BOUND_SIZE*d_GRID_Y_OFFSET];

				//Right Down
				s_lnrho[sid_row+RK_THREADS_Y][sid_col + RK_THREADS_X] = d_lnrho[grid_idx + RK_THREADS_X + RK_THREADS_Y*d_GRID_Y_OFFSET];
				//s_uu_x [sid_row+RK_THREADS_Y][sid_col + RK_THREADS_X] = d_uu_x[grid_idx + RK_THREADS_X + RK_THREADS_Y*d_GRID_Y_OFFSET];
				s_uu_y [sid_row+RK_THREADS_Y][sid_col + RK_THREADS_X] = d_uu_y[grid_idx + RK_THREADS_X + RK_THREADS_Y*d_GRID_Y_OFFSET];
				s_uu_z [sid_row+RK_THREADS_Y][sid_col + RK_THREADS_X] = d_uu_z[grid_idx + RK_THREADS_X + RK_THREADS_Y*d_GRID_Y_OFFSET];
			}
		__syncthreads();
		
		
			
		//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		
			
			der2_scalxz(sid_row, sid_col, s_uu_z, diagonal_result_xz_uuz);		
			der2_scalyz(sid_row, sid_col, s_uu_z, diagonal_result_yz_uuz);
			//der2_scalxz(sid_row, sid_col, s_uu_x, diagonal_result_xz_uux);
			der2_scalyz(sid_row, sid_col, s_uu_y, diagonal_result_yz_uuy);

	
			if(zplane >= 0 && zplane < RK_ELEMS_PER_THREAD_FIRST){

				//const float d2x_uu_x = der2_scalx(sid_row, sid_col, s_uu_x);
				d2xy_uu_y = der2_scalxy(sid_row, sid_col, s_uu_y);
				//const float d2xy_uu_x = der2_scalxy(sid_row, sid_col, s_uu_x);
				d2y_uu_y = der2_scaly(sid_row, sid_col, s_uu_y);
				d2z_uu_z = der2_scalz(sid_row, sid_col, s_uu_z, behind3_uu_z, behind2_uu_z, behind1_uu_z, 
											infront1_uu_z, infront2_uu_z, infront3_uu_z);
			 
				//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

				//Solve derivatives
				ddz_lnrho = der_scalz( behind3_lnrho, behind2_lnrho, behind1_lnrho, 
		                                           infront1_lnrho, infront2_lnrho, infront3_lnrho );
				ddz_uu_x =  der_scalz( behind3_uu_x, behind2_uu_x, behind1_uu_x, 
		                                           infront1_uu_x, infront2_uu_x, infront3_uu_x );
				ddz_uu_y =  der_scalz( behind3_uu_y, behind2_uu_y, behind1_uu_y, 
		                                           infront1_uu_y, infront2_uu_y, infront3_uu_y );
				ddz_uu_z =  der_scalz( behind3_uu_z, behind2_uu_z, behind1_uu_z, 
		                                           infront1_uu_z, infront2_uu_z, infront3_uu_z );
	
				ddx_lnrho = der_scalx(sid_row, sid_col, s_lnrho);
				//ddx_uu_x  = der_scalx(sid_row, sid_col, s_uu_x);
				ddx_uu_y  = der_scalx(sid_row, sid_col, s_uu_y);
				ddx_uu_z  = der_scalx(sid_row, sid_col, s_uu_z);

				ddy_lnrho = der_scaly(sid_row, sid_col, s_lnrho);
				//ddy_uu_x  = der_scaly(sid_row, sid_col, s_uu_x);
				ddy_uu_y  = der_scaly(sid_row, sid_col, s_uu_y);
				ddy_uu_z  = der_scaly(sid_row, sid_col, s_uu_z);

	
				//Save the divergence field of uu to global memory
				//d_div_uu[grid_idx] = ddx_uu_x + ddy_uu_y + ddz_uu_z; // Omer: nebla.u_i Eq(.1)
			}
			__syncthreads();
			//:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::://
			s_uu_x = SM;
			s_uu_x[sid_row][sid_col] = current_uu_x;
			//Load halos (not optimal)
			if (threadIdx.x < BOUND_SIZE) {
		
				//Load left
				s_uu_x [sid_row][sid_col-BOUND_SIZE] = d_uu_x [grid_idx - BOUND_SIZE];

				//Load right
				s_uu_x [sid_row][sid_col+RK_THREADS_X] = d_uu_x [grid_idx+RK_THREADS_X];
			
			}
			if (threadIdx.y < BOUND_SIZE) {
				//Load down
				s_uu_x [sid_row-BOUND_SIZE][sid_col] = d_uu_x [grid_idx - BOUND_SIZE*d_GRID_Y_OFFSET];
				
				//Load up
				s_uu_x [sid_row+RK_THREADS_Y][sid_col] = d_uu_x [grid_idx + RK_THREADS_Y*d_GRID_Y_OFFSET];
			}
			if(threadIdx.x < BOUND_SIZE && threadIdx.y < BOUND_SIZE){
				//Load corners of size 3x3 of halo zones not loaded above in shared memory
				//Left Up
				s_uu_x [sid_row-BOUND_SIZE][sid_col-BOUND_SIZE] = d_uu_x[grid_idx - BOUND_SIZE - BOUND_SIZE*d_GRID_Y_OFFSET];
				
				//Left Down
				s_uu_x [sid_row+RK_THREADS_Y][sid_col-BOUND_SIZE] = d_uu_x[grid_idx - BOUND_SIZE + RK_THREADS_Y*d_GRID_Y_OFFSET];
				
				//Right Up
				s_uu_x [sid_row-BOUND_SIZE][sid_col+RK_THREADS_X] = d_uu_x[grid_idx + RK_THREADS_X - BOUND_SIZE*d_GRID_Y_OFFSET];
		
				//Right Down
				s_uu_x [sid_row+RK_THREADS_Y][sid_col + RK_THREADS_X] = d_uu_x[grid_idx + RK_THREADS_X + RK_THREADS_Y*d_GRID_Y_OFFSET];
			}
			__syncthreads();

			der2_scalxz(sid_row, sid_col, s_uu_x, diagonal_result_xz_uux);
			//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
			if(zplane >= 0 && zplane < RK_ELEMS_PER_THREAD_FIRST){

				d2x_uu_x = der2_scalx(sid_row, sid_col, s_uu_x);
				d2xy_uu_x = der2_scalxy(sid_row, sid_col, s_uu_x);
				//Solve derivatives
				ddx_uu_x  = der_scalx(sid_row, sid_col, s_uu_x);
				ddy_uu_x  = der_scaly(sid_row, sid_col, s_uu_x);
				
				//ILP: compute nu_const_uu and S_grad_lnrho before using cont_res  //Omer: Eq(.6)
				nu_const_uu_x = der2_scalx(sid_row, sid_col, s_uu_x) +
		                                    der2_scaly(sid_row, sid_col, s_uu_x) +
		                                    der2_scalz(sid_row, sid_col, s_uu_x, 
		                                               behind3_uu_x, behind2_uu_x, behind1_uu_x, 
		                                               infront1_uu_x, infront2_uu_x, infront3_uu_x);
			}
			//::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::://
			
			if(zplane >= 0 && zplane < RK_ELEMS_PER_THREAD_FIRST){
				
				//Continuity	
				const float cont_res = - (current_uu_x * ddx_lnrho +
		                                  current_uu_y * ddy_lnrho +
		                                  current_uu_z * ddz_lnrho) 
		                               - (ddx_uu_x + ddy_uu_y + ddz_uu_z);  // Omer: -(u.nebla)rho - nebla.u  Eq(.2)

				const float nu_const_uu_y = der2_scalx(sid_row, sid_col, s_uu_y) +
		                                    der2_scaly(sid_row, sid_col, s_uu_y) +
		                                    der2_scalz(sid_row, sid_col, s_uu_y, 
		                                               behind3_uu_y, behind2_uu_y, behind1_uu_y, 
		                                               infront1_uu_y, infront2_uu_y, infront3_uu_y);
				const float nu_const_uu_z = der2_scalx(sid_row, sid_col, s_uu_z) +
		                                    der2_scaly(sid_row, sid_col, s_uu_z) +
		                                    der2_scalz(sid_row, sid_col, s_uu_z, 
		                                               behind3_uu_z, behind2_uu_z, behind1_uu_z, 
		                                               infront1_uu_z, infront2_uu_z, infront3_uu_z);

				//S_grad_lnrho  //Eq(.9)
				const float Sxx = (2.0f/3.0f)*ddx_uu_x - (1.0f/3.0f)*(ddy_uu_y + ddz_uu_z);
				const float Sxy = 0.5f*(ddy_uu_x + ddx_uu_y);
				const float Sxz = 0.5f*(ddz_uu_x + ddx_uu_z);
				const float Syy = (2.0f/3.0f)*ddy_uu_y - (1.0f/3.0f)*(ddx_uu_x + ddz_uu_z);
				const float Syz = 0.5f*(ddz_uu_y + ddy_uu_z);
				const float Szz = (2.0f/3.0f)*ddz_uu_z - (1.0f/3.0f)*(ddx_uu_x + ddy_uu_y);

				//Use cont_res to compute w_lnrho
				w_lnrho = ALPHA*w_lnrho + d_DT*cont_res; //Omer: Second line Algo. 3 updating rho

				//Navier-Stokes
				mom_x[0] = - (s_uu_x[sid_row][sid_col] * ddx_uu_x +               //vec_dot_nabla_scal
		                               s_uu_y[sid_row][sid_col] * ddy_uu_x +
		                               s_uu_z[sid_row][sid_col] * ddz_uu_x)
		                            - d_CS2_SOUND*ddx_lnrho                                //ddx part of grad lnrho
		                            + d_NU_VISC * nu_const_uu_x                            //nu_const 
		                            + 2.0f*d_NU_VISC*(Sxx*ddx_lnrho + Sxy*ddy_lnrho + Sxz*ddz_lnrho)+d_NU_VISC*(1.0f/3.0f)*(d2x_uu_x + d2xy_uu_y); //S_grad_lnrho

				mom_y[0] = - (s_uu_x[sid_row][sid_col] * ddx_uu_y +               //vec_dot_nabla_scal
		                               s_uu_y[sid_row][sid_col] * ddy_uu_y +
		                               s_uu_z[sid_row][sid_col] * ddz_uu_y)
		                            - d_CS2_SOUND*ddy_lnrho                                //ddy part of grad lnrho
		                            + d_NU_VISC * nu_const_uu_y                            //nu_const
		                            + 2.0f*d_NU_VISC*(Sxy*ddx_lnrho + Syy*ddy_lnrho + Syz*ddz_lnrho)+d_NU_VISC*(1.0f/3.0f)*(d2xy_uu_x + d2y_uu_y); //S_grad_lnrho

				mom_z[0] = - (s_uu_x[sid_row][sid_col] * ddx_uu_z +               //vec_dot_nabla_scal
		                               s_uu_y[sid_row][sid_col] * ddy_uu_z +
		                               s_uu_z[sid_row][sid_col] * ddz_uu_z)
		                            - d_CS2_SOUND*ddz_lnrho                                //ddz part of grad lnrho
		                            + d_NU_VISC * nu_const_uu_z                            //nu_const
		                            + 2.0f*d_NU_VISC*(Sxz*ddx_lnrho + Syz*ddy_lnrho + Szz*ddz_lnrho)+d_NU_VISC*(1.0f/3.0f)*d2z_uu_z; //S_grad_lnrho
				

				d_lnrho_dest[grid_idx] = s_lnrho[sid_row][sid_col] + BETA*w_lnrho;
			}
				//use the output which is mature now 

				if(zplane - 3 >= 0 && zplane - 3 < RK_ELEMS_PER_THREAD_FIRST) {
				div_z_partial_ux[0] -= diagonal_result_xz_uuz[2];
				div_z_partial_uy[0] -= diagonal_result_yz_uuz[2];
				div_z_partial_uz[0] -= (diagonal_result_xz_uux[2]+ diagonal_result_yz_uuy[2]);
				}
				if(zplane - 2 >= 0 && zplane - 2 < RK_ELEMS_PER_THREAD_FIRST) {
					div_z_partial_ux[1] -= diagonal_result_xz_uuz[1];
					div_z_partial_uy[1] -= diagonal_result_yz_uuz[1];
					div_z_partial_uz[1] -= (diagonal_result_xz_uux[1]+ diagonal_result_yz_uuy[1]);
				}
				if(zplane - 1 >= 0 && zplane - 1 < RK_ELEMS_PER_THREAD_FIRST) {
					div_z_partial_ux[2] -= diagonal_result_xz_uuz[0];
					div_z_partial_uy[2] -= diagonal_result_yz_uuz[0];
					div_z_partial_uz[2] -= (diagonal_result_xz_uux[0]+ diagonal_result_yz_uuy[0]);
				}
				// div_z_partial_xx[3] += 0;
				if(zplane + 1 >= 0 && zplane + 1 < RK_ELEMS_PER_THREAD_FIRST) {
					div_z_partial_ux[4] += diagonal_result_xz_uuz[0];
					div_z_partial_uy[4] += diagonal_result_yz_uuz[0];
					div_z_partial_uz[4] += (diagonal_result_xz_uux[0]+ diagonal_result_yz_uuy[0]);
				}
				if(zplane + 2 >= 0 && zplane + 2 < RK_ELEMS_PER_THREAD_FIRST) {
					div_z_partial_ux[5] += diagonal_result_xz_uuz[1];
					div_z_partial_uy[5] += diagonal_result_yz_uuz[1];
					div_z_partial_uz[5] += (diagonal_result_xz_uux[1]+ diagonal_result_yz_uuy[1]);
				}
				if(zplane + 3 >= 0 && zplane + 3 < RK_ELEMS_PER_THREAD_FIRST) {
					div_z_partial_ux[6] += diagonal_result_xz_uuz[2];
					div_z_partial_uy[6] += diagonal_result_yz_uuz[2];
					div_z_partial_uz[6] += (diagonal_result_xz_uux[2]+ diagonal_result_yz_uuy[2]);
				}

				if(zplane - 3 >= 0) {
					const float div_uux = d_NU_VISC*(1.0f/3.0f)*(div_z_partial_ux[0]); 
					const float div_uuy = d_NU_VISC*(1.0f/3.0f)*(div_z_partial_uy[0]);
					const float div_uuz = d_NU_VISC*(1.0f/3.0f)*(div_z_partial_uz[0]);

					w_uu_x = ALPHA*w_uu_x + d_DT*(mom_x[3] + div_uux);
					w_uu_y = ALPHA*w_uu_y + d_DT*(mom_y[3] + div_uuy);
					w_uu_z = ALPHA*w_uu_z + d_DT*(mom_z[3] + div_uuz);
				
					d_uu_x_dest [grid_idx-3*d_GRID_Z_OFFSET] = (behind3_uu_x + BETA*w_uu_x);
					d_uu_y_dest [grid_idx-3*d_GRID_Z_OFFSET] = behind3_uu_y + BETA*w_uu_y;
					d_uu_z_dest [grid_idx-3*d_GRID_Z_OFFSET] = behind3_uu_z + BETA*w_uu_z;	

					d_w_lnrho[w_grid_idx] = w_lnrho;
					d_w_uu_x [w_grid_idx] = w_uu_x;
					d_w_uu_y [w_grid_idx] = w_uu_y;
					d_w_uu_z [w_grid_idx] = w_uu_z;
					
					w_grid_idx += d_W_GRID_Z_OFFSET;
				}
		
				// Shift
				div_z_partial_ux[0] = div_z_partial_ux[1];
				div_z_partial_ux[1] = div_z_partial_ux[2];
				div_z_partial_ux[2] = div_z_partial_ux[3];
				div_z_partial_ux[3] = div_z_partial_ux[4];
				div_z_partial_ux[4] = div_z_partial_ux[5];
				div_z_partial_ux[5] = div_z_partial_ux[6];
				div_z_partial_ux[6] = 0;		

				div_z_partial_uy[0] = div_z_partial_uy[1];
				div_z_partial_uy[1] = div_z_partial_uy[2];
				div_z_partial_uy[2] = div_z_partial_uy[3];
				div_z_partial_uy[3] = div_z_partial_uy[4];
				div_z_partial_uy[4] = div_z_partial_uy[5];
				div_z_partial_uy[5] = div_z_partial_uy[6];
				div_z_partial_uy[6] = 0;		

				div_z_partial_uz[0] = div_z_partial_uz[1];
				div_z_partial_uz[1] = div_z_partial_uz[2];
				div_z_partial_uz[2] = div_z_partial_uz[3];
				div_z_partial_uz[3] = div_z_partial_uz[4];
				div_z_partial_uz[4] = div_z_partial_uz[5];
				div_z_partial_uz[5] = div_z_partial_uz[6];
				div_z_partial_uz[6] = 0;	
				
				mom_x[3] = mom_x[2];
				mom_x[2] = mom_x[1];
				mom_x[1] = mom_x[0];

							
			
			//else continue
			grid_idx += d_GRID_Z_OFFSET;
			

			//Reuse data in registers and update infront3
			behind3_lnrho  = behind2_lnrho;
			behind2_lnrho  = behind1_lnrho;
			behind1_lnrho  = s_lnrho[sid_row][sid_col];
			current_lnrho  = infront1_lnrho;
			infront1_lnrho = infront2_lnrho;
			infront2_lnrho = infront3_lnrho;
			infront3_lnrho = d_lnrho[grid_idx + 3*d_GRID_Z_OFFSET];

			behind3_uu_x  = behind2_uu_x;
			behind2_uu_x  = behind1_uu_x;
			behind1_uu_x  = s_uu_x[sid_row][sid_col];
			current_uu_x  = infront1_uu_x;
			infront1_uu_x = infront2_uu_x;
			infront2_uu_x = infront3_uu_x;
			infront3_uu_x = d_uu_x[grid_idx + 3*d_GRID_Z_OFFSET];

			behind3_uu_y  = behind2_uu_y;
			behind2_uu_y  = behind1_uu_y;
			behind1_uu_y  = s_uu_y[sid_row][sid_col];
			current_uu_y  = infront1_uu_y;
			infront1_uu_y = infront2_uu_y;
			infront2_uu_y = infront3_uu_y;
			infront3_uu_y = d_uu_y[grid_idx + 3*d_GRID_Z_OFFSET];

			behind3_uu_z  = behind2_uu_z;
			behind2_uu_z  = behind1_uu_z;
			behind1_uu_z  = s_uu_z[sid_row][sid_col];
			current_uu_z  = infront1_uu_z;
			infront1_uu_z = infront2_uu_z;
			infront2_uu_z = infront3_uu_z;
			infront3_uu_z = d_uu_z[grid_idx + 3*d_GRID_Z_OFFSET];
		__syncthreads();

	}// loop ends

//if ( blockIdx.x == 3 && blockIdx.y == 31 && blockIdx.z == 15){
//		printf("%d---%d---%d current_iteration = %d \n", threadIdx.x,threadIdx.y,threadIdx.z,current_iteration);
//}

}


//----------------------------------------------------------
// Manages the calculation on 2N-Runge-Kutta for a single timestep
//----------------------------------------------------------
void rungekutta2N_cuda(	float* d_lnrho, float* d_uu_x, float* d_uu_y, float* d_uu_z, 
                  	float* d_w_lnrho, float* d_w_uu_x, float* d_w_uu_y, float* d_w_uu_z,
			float* d_lnrho_dest, float* d_uu_x_dest, float* d_uu_y_dest, float* d_uu_z_dest)
{
	//Determine threadblock dims (TODO better solution, define?)
	static dim3 threadsPerBlock, blocksPerGridFirst, blocksPerGridSecond;
	threadsPerBlock.x = RK_THREADS_X; //RK_THREADS_X = 32
	threadsPerBlock.y = RK_THREADS_Y; //RK_THREADS_Y = 4
	threadsPerBlock.z = RK_THREADS_Z; //RK_THREADS_Z = 1
	assert(RK_THREADS_Z == 1);

	blocksPerGridFirst.x = ceil((float) COMP_DOMAIN_SIZE_X / (float)threadsPerBlock.x); //128 / 32 = 4
	blocksPerGridFirst.y = ceil((float) COMP_DOMAIN_SIZE_Y / (float)threadsPerBlock.y); //128 / 4 = 32
	blocksPerGridFirst.z = ceil((float) COMP_DOMAIN_SIZE_Z / (float)(threadsPerBlock.z*RK_ELEMS_PER_THREAD_FIRST)); //128 / (1*8) = 16 

	blocksPerGridSecond.x = ceil((float) COMP_DOMAIN_SIZE_X / (float)threadsPerBlock.x);
	blocksPerGridSecond.y = ceil((float) COMP_DOMAIN_SIZE_Y / (float)threadsPerBlock.y);
	blocksPerGridSecond.z = ceil((float) COMP_DOMAIN_SIZE_Z / (float)(threadsPerBlock.z*RK_ELEMS_PER_THREAD_SECOND));

	//Calculate steps in kernels 
	// Step 1:
	//-------------------------------------------------------------------------------------------------------------------------------
	//FIRST HALF
	//TIME START
	cudaEvent_t start, stop;
	float time;
	cudaEventCreate(&start);
	cudaEventCreate(&stop);
	cudaEventRecord( start, 0 );

        rungekutta_step_first_half<0><<<blocksPerGridFirst, threadsPerBlock>>>(d_lnrho, d_uu_x, d_uu_y, d_uu_z, 
                                                                               d_w_lnrho, d_w_uu_x, d_w_uu_y, d_w_uu_z, 
                                                                               d_lnrho_dest, d_uu_x_dest, d_uu_y_dest, d_uu_z_dest);
       
	
	//TIME END
	cudaEventRecord( stop, 0 );
	cudaEventSynchronize( stop );
	cudaEventElapsedTime( &time, start, stop );
	cudaEventDestroy( start );
	cudaEventDestroy( stop );
	printf("A Single rungekutta step time elapsed: \t%f ms\n", time);

	cudaDeviceSynchronize(); // should be moved up after the kernel launch for correct timing 

}










