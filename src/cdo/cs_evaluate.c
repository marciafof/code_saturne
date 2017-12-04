/*============================================================================
 * Functions and structures to deal with evaluation of quantities
 *============================================================================*/

/*
  This file is part of Code_Saturne, a general-purpose CFD tool.

  Copyright (C) 1998-2017 EDF S.A.

  This program is free software; you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free Software
  Foundation; either version 2 of the License, or (at your option) any later
  version.

  This program is distributed in the hope that it will be useful, but WITHOUT
  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
  FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
  details.

  You should have received a copy of the GNU General Public License along with
  this program; if not, write to the Free Software Foundation, Inc., 51 Franklin
  Street, Fifth Floor, Boston, MA 02110-1301, USA.
*/

#include "cs_defs.h"

/*----------------------------------------------------------------------------
 * Standard C library headers
 *----------------------------------------------------------------------------*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <float.h>

/*----------------------------------------------------------------------------
 * Local headers
 *----------------------------------------------------------------------------*/

#include <bft_mem.h>

#include "cs_halo.h"
#include "cs_math.h"
#include "cs_mesh.h"
#include "cs_parall.h"
#include "cs_range_set.h"
#include "cs_volume_zone.h"

/*----------------------------------------------------------------------------
 * Header for the current file
 *----------------------------------------------------------------------------*/

#include "cs_evaluate.h"

/*----------------------------------------------------------------------------*/

BEGIN_C_DECLS

/*=============================================================================
 * Local Macro definitions and structure definitions
 *============================================================================*/

/* Pointer to shared structures (owned by a cs_domain_t structure) */
static const cs_cdo_quantities_t  *cs_cdo_quant;
static const cs_cdo_connect_t  *cs_cdo_connect;
static const cs_time_step_t  *cs_time_step;

static const char _err_empty_array[] =
  " %s: Array storing the evaluation should be allocated before the call"
  " to this function.";
static const char _err_not_handled[] = " %s: Case not handled yet.";

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Compute the integral over a tetrahedron based on a specified
 *         quadrature rules
 *
 * \param[in]      tcur     current physical time of the simulation
 * \param[in]      xv       first point of the tetrahedron
 * \param[in]      xe       second point of the tetrahedron
 * \param[in]      xf       third point of the tetrahedron
 * \param[in]      xc       fourth point of the tetrahedron
 * \param[in]      ana      pointer to the analytic function
 * \param[in]      input    NULL or pointer to a structure cast on-the-fly
 * \param[in, out] results  array of double
 */
/*----------------------------------------------------------------------------*/

typedef void
(cs_evaluate_tetra_integral_t)(double                 tcur,
                               const cs_real_3_t      xv,
                               const cs_real_3_t      xe,
                               const cs_real_3_t      xf,
                               const cs_real_3_t      xc,
                               cs_analytic_func_t    *ana,
                               void                  *input,
                               double                 results[]);

/*============================================================================
 * Private function prototypes
 *============================================================================*/

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Compute the integral over a tetrahedron of the barycentric subdiv.
 *         using a barycentric quadrature rule
 *
 * \param[in]  tcur         current physical time of the simulation
 * \param[in]  xv           first point of the tetrahedron
 * \param[in]  xe           second point of the tetrahedron
 * \param[in]  xf           third point of the tetrahedron
 * \param[in]  xc           fourth point of the tetrahedron
 * \param[in]  ana          pointer to the analytic function
 * \param[in]  input        NULL or pointer to a structure cast on-the-fly
 * \param[in, out] results  array of double
 */
/*----------------------------------------------------------------------------*/

inline static void
_analytic_scalar_tet1(double                 tcur,
                      const cs_real_3_t      xv,
                      const cs_real_3_t      xe,
                      const cs_real_3_t      xf,
                      const cs_real_3_t      xc,
                      cs_analytic_func_t    *ana,
                      void                  *input,
                      double                 results[])
{
  int  k;
  cs_real_3_t  xg;
  double  evaluation;

  const double  vol_tet = cs_math_voltet(xv, xe, xf, xc);

  for (k = 0; k < 3; k++)
    xg[k] = 0.25*(xv[k] + xe[k] + xf[k] + xc[k]);

  ana(tcur, 1, NULL, xg, true, input, &evaluation);

  *results += vol_tet * evaluation;
}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Compute the integral over a tetrahedron of the barycentric subdiv.
 *         with a quadrature rule using 4 Gauss points and a unique weight
 *
 * \param[in]  tcur         current physical time of the simulation
 * \param[in]  xv           first point of the tetrahedron
 * \param[in]  xe           second point of the tetrahedron
 * \param[in]  xf           third point of the tetrahedron
 * \param[in]  xc           fourth point of the tetrahedron
 * \param[in]  ana          pointer to the analytic function
 * \param[in]  input        NULL or pointer to a structure cast on-the-fly
 * \param[in, out] results  array of double
 */
/*----------------------------------------------------------------------------*/

inline static void
_analytic_scalar_tet4(double                tcur,
                      const cs_real_3_t     xv,
                      const cs_real_3_t     xe,
                      const cs_real_3_t     xf,
                      const cs_real_3_t     xc,
                      cs_analytic_func_t   *ana,
                      void                 *input,
                      double                results[])
{
  cs_real_3_t  gauss_pts[4];
  double  evaluation[4], weights[4];

  const double  vol_tet = cs_math_voltet(xv, xe, xf, xc);

  /* Compute Gauss points and its unique weight */
  cs_quadrature_tet_4pts(xv, xe, xf, xc, vol_tet, gauss_pts, weights);

  ana(tcur, 4, NULL, (const cs_real_t *)gauss_pts, true, input, evaluation);

  double  add = 0.0;
  for (int p = 0; p < 4; p++) add += weights[p] * evaluation[p];

  /* Return results */
  *results += add;
}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Compute the integral over a tetrahedron of the barycentric subdiv.
 *         with a quadrature rule using 5 Gauss points and 5 weights
 *
 * \param[in]  tcur         current physical time of the simulation
 * \param[in]  xv           first point of the tetrahedron
 * \param[in]  xe           second point of the tetrahedron
 * \param[in]  xf           third point of the tetrahedron
 * \param[in]  xc           fourth point of the tetrahedron
 * \param[in]  ana          pointer to the analytic function
 * \param[in]  input        NULL or pointer to a structure cast on-the-fly
 * \param[in, out] results  array of double
 */
/*----------------------------------------------------------------------------*/

inline static void
_analytic_scalar_tet5(double                tcur,
                      const cs_real_3_t     xv,
                      const cs_real_3_t     xe,
                      const cs_real_3_t     xf,
                      const cs_real_3_t     xc,
                      cs_analytic_func_t   *ana,
                      void                 *input,
                      double                results[])
{
  cs_real_t  weights[5], evaluation[5];
  cs_real_3_t  gauss_pts[5];

  const double  vol_tet = cs_math_voltet(xv, xe, xf, xc);

  /* Compute Gauss points and its weights */
  cs_quadrature_tet_5pts(xv, xe, xf, xc, vol_tet, gauss_pts, weights);

  ana(tcur, 5, NULL, (const cs_real_t *)gauss_pts, true, input, evaluation);

  double  add = 0.0;
  for (int p = 0; p < 5; p++) add += evaluation[p] * weights[p];

  *results += add;
}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Compute the integral over dual cells of a scalar density field
 *         defined by an analytical function on a cell
 *
 * \param[in]      cm                pointer to a cs_cell_mesh_t structure
 * \param[in]      ana               pointer to the analytic function
 * \param[in]      input             NULL or pointer cast on-the-fly
 * \param[in]      compute_integral  function pointer
 * \param[in, out] values            pointer to the computed values
 */
/*----------------------------------------------------------------------------*/

static void
_cellwise_dcsd_by_analytic(const cs_cell_mesh_t           *cm,
                           cs_analytic_func_t             *ana,
                           void                           *input,
                           cs_evaluate_tetra_integral_t   *compute_integral,
                           double                          values[])
{
  const double  tcur = cs_time_step->t_cur;

  for (short int f = 0; f < cm->n_fc; f++) {

    const double  *xf = cm->face[f].center;
    const short int  n_ef = cm->f2e_idx[f+1] - cm->f2e_idx[f];
    const short int  *e_ids = cm->f2e_ids + cm->f2e_idx[f];

    for (short int i = 0; i < n_ef; i++) {

      const short int  e = e_ids[i];
      const short int  v1 = cm->e2v_ids[2*e];
      const short int  v2 = cm->e2v_ids[2*e+1];
      const double  *xv1 = cm->xv + 3*v1, *xv2 = cm->xv + 3*v2;
      const double  *xe = cm->edge[e].center;

      compute_integral(tcur, xv1, xe, xf, cm->xc, ana, input, values + v1);
      compute_integral(tcur, xv2, xe, xf, cm->xc, ana, input, values + v2);

    } // Loop on face edges

  } // Loop on cell faces

}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Compute the integral over dual cells of a scalar density field
 *         defined by an analytical function on a selection of (primal) cells
 *
 * \param[in]      ana               pointer to the analytic function
 * \param[in]      input             NULL or pointer cast on-the-fly
 * \param[in]      n_loc_elts        number of elements to consider
 * \param[in]      elt_ids           pointer to the list od selected ids
 * \param[in]      compute_integral  function pointer
 * \param[in, out] values            pointer to the computed values
 */
/*----------------------------------------------------------------------------*/

static void
_dcsd_by_analytic(cs_analytic_func_t            *ana,
                  void                          *input,
                  const cs_lnum_t                n_elts,
                  const cs_lnum_t               *elt_ids,
                  cs_evaluate_tetra_integral_t  *compute_integral,
                  double                         values[])
{
  const cs_cdo_quantities_t  *quant = cs_cdo_quant;
  const cs_cdo_connect_t  *connect = cs_cdo_connect;
  const cs_adjacency_t  *c2f = connect->c2f;
  const cs_adjacency_t  *f2e = connect->f2e;
  const double  tcur = cs_time_step->t_cur;

  /* Compute dual volumes */
  for (cs_lnum_t  id = 0; id < n_elts; id++) {

    const cs_lnum_t  c_id = (elt_ids == NULL) ? id : elt_ids[id];
    const cs_real_t  *xc = quant->cell_centers + 3*c_id;

    for (cs_lnum_t i = c2f->idx[c_id]; i < c2f->idx[c_id+1]; i++) {

      const cs_lnum_t  f_id = c2f->ids[i];
      const cs_real_t  *xf = cs_quant_set_face_center(f_id, quant);

      for (cs_lnum_t j = f2e->idx[f_id]; j < f2e->idx[f_id+1]; j++) {

        const cs_lnum_t  e_id = f2e->ids[j];
        const cs_lnum_t  v1 = connect->e2v->ids[2*e_id];
        const cs_lnum_t  v2 = connect->e2v->ids[2*e_id+1];
        const cs_real_t  *xv1 = quant->vtx_coord + 3*v1;
        const cs_real_t  *xv2 = quant->vtx_coord + 3*v2;

        cs_real_3_t  xe;
        for (int k = 0; k < 3; k++)
          xe[k] = 0.5 * (xv1[k] + xv2[k]);

        compute_integral(tcur, xv1, xe, xf, xc, ana, input, values + v1);
        compute_integral(tcur, xv2, xe, xf, xc, ana, input, values + v2);

      } // Loop on edges

    } // Loop on faces

  } // Loop on cells

}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Compute the integral over primal cells of a scalar density field
 *         defined by an analytical function on a cell
 *
 * \param[in]      cm                pointer to a cs_cell_mesh_t structure
 * \param[in]      ana               pointer to the analytic function
 * \param[in]      input             NULL or pointer cast on-the-fly
 * \param[in]      compute_integral  function pointer
 *
 * \return the value of the corresponding integral
 */
/*----------------------------------------------------------------------------*/

static double
_cellwise_pcsd_by_analytic(const cs_cell_mesh_t          *cm,
                           cs_analytic_func_t            *ana,
                           void                          *input,
                           cs_evaluate_tetra_integral_t  *compute_integral)
{
  const double  tcur = cs_time_step->t_cur;

  double  retval = 0.;

  if (cs_cdo_connect->cell_type[cm->c_id] == FVM_CELL_TETRA) {

    compute_integral(tcur, cm->xv, cm->xv + 3, cm->xv + 6, cm->xv + 9,
                     ana, input, &retval);

  }
  else {

    for (short int f = 0; f < cm->n_fc; f++) {

      const short int  n_ef = cm->f2e_idx[f+1] - cm->f2e_idx[f];
      const short int  *e_ids = cm->f2e_ids + cm->f2e_idx[f];

      if (n_ef == 3) { // Current face is a triangle --> simpler

        short int  v0, v1, v2;
        cs_cell_mesh_get_next_3_vertices(e_ids, cm->e2v_ids, &v0, &v1, &v2);

        const double *xv0 = cm->xv+3*v0, *xv1 = cm->xv+3*v1, *xv2 = cm->xv+3*v2;

        compute_integral(tcur, xv0, xv1, xv2, cm->xc, ana, input, &retval);

      }
      else {

        const double  *xf = cm->face[f].center;

        for (short int i = 0; i < n_ef; i++) {

          const short int  _2e = 2*e_ids[i];
          const double  *xv1 = cm->xv + 3*cm->e2v_ids[_2e];
          const double  *xv2 = cm->xv + 3*cm->e2v_ids[_2e+1];

          compute_integral(tcur, xv1, xv2, xf, cm->xc, ana, input, &retval);

        } // Loop on face edges

      } // Current face is triangle or not ?

    } // Loop on cell faces

  } // Not a tetrahedron

  return retval;
}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Compute the integral over primal cells of a scalar density field
 *         defined by an analytical function on a selection of (primal) cells
 *
 * \param[in]      ana               pointer to the analytic function
 * \param[in]      input             NULL or pointer cast on-the-fly
 * \param[in]      n_loc_elts        number of elements to consider
 * \param[in]      elt_ids           pointer to the list od selected ids
 * \param[in]      compute_integral  function pointer
 * \param[in, out] values            pointer to the computed values
 */
/*----------------------------------------------------------------------------*/

static void
_pcsd_by_analytic(cs_analytic_func_t            *ana,
                  void                          *input,
                  const cs_lnum_t                n_elts,
                  const cs_lnum_t               *elt_ids,
                  cs_evaluate_tetra_integral_t  *compute_integral,
                  double                         values[])
{
  const cs_cdo_quantities_t  *quant = cs_cdo_quant;
  const cs_real_t  *xv = quant->vtx_coord;
  const cs_cdo_connect_t  *connect = cs_cdo_connect;
  const cs_adjacency_t  *c2f = connect->c2f;
  const cs_adjacency_t  *f2e = connect->f2e;
  const double  tcur = cs_time_step->t_cur;

  for (cs_lnum_t  id = 0; id < n_elts; id++) {

    const cs_lnum_t  c_id = (elt_ids == NULL) ? id : elt_ids[id];
    if (connect->cell_type[c_id] == FVM_CELL_TETRA) {

      const cs_lnum_t  *v_ids = connect->c2v->ids + connect->c2v->idx[c_id];

      compute_integral(tcur,
                       xv + 3*v_ids[0], xv + 3*v_ids[1], xv + 3*v_ids[2],
                       xv + 3*v_ids[3],
                       ana, input,
                       values + c_id);


    }
    else {

      const cs_real_t  *xc = quant->cell_centers + 3*c_id;

      for (cs_lnum_t i = c2f->idx[c_id]; i < c2f->idx[c_id+1]; i++) {

        const cs_lnum_t  f_id = c2f->ids[i];
        const cs_real_t  *xf = cs_quant_set_face_center(f_id, quant);

        for (cs_lnum_t j = f2e->idx[f_id]; j < f2e->idx[f_id+1]; j++) {

          const cs_lnum_t  _2e = 2*f2e->ids[j];
          const cs_lnum_t  v1 = connect->e2v->ids[_2e];
          const cs_lnum_t  v2 = connect->e2v->ids[_2e+1];

          compute_integral(tcur, xv + 3*v1, xv + 3*v2, xf, xc,
                           ana, input, values + c_id);

        } // Loop on edges

      } // Loop on faces

    } /* Not a tetrahedron */

  } // Loop on cells

}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Compute the integral over a dual cell (or a portion) of a value
 *         defined on a selection of (primal) cells
 *
 * \param[in]      const_val   constant value
 * \param[in]      n_loc_elts  number of elements to consider
 * \param[in]      elt_ids     pointer to the list od selected ids
 * \param[in, out] values      pointer to the computed values
 */
/*----------------------------------------------------------------------------*/

static void
_dcsd_by_value(const double       const_val,
               const cs_lnum_t    n_elts,
               const cs_lnum_t   *elt_ids,
               double             values[])
{
  const cs_adjacency_t  *c2v = cs_cdo_connect->c2v;
  const cs_cdo_quantities_t  *quant = cs_cdo_quant;
  const cs_real_t  *dual_vol = quant->dcell_vol; /* scan by c2v */

  if (elt_ids == NULL) {

    assert(n_elts == quant->n_cells);
    for (cs_lnum_t c_id = 0; c_id < n_elts; c_id++)
      for (cs_lnum_t j = c2v->idx[c_id]; j < c2v->idx[c_id+1]; j++)
        values[c2v->ids[j]] += dual_vol[j]*const_val;

  }
  else { /* Loop on selected cells */

    for (cs_lnum_t i = 0; i < n_elts; i++) {
      cs_lnum_t  c_id = elt_ids[i];
      for (cs_lnum_t  j = c2v->idx[c_id]; j < c2v->idx[c_id+1]; j++)
        values[c2v->ids[j]] += dual_vol[j]*const_val;
    }

  }

}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Compute the integral over a dual cell (or a portion) of a
 *         vector-valued density field defined on a selection of (primal) cells
 *
 * \param[in]      const_vec   constant vector
 * \param[in]      n_loc_elts  number of elements to consider
 * \param[in]      elt_ids     pointer to the list od selected ids
 * \param[in, out] values      pointer to the computed values
 */
/*----------------------------------------------------------------------------*/

static void
_dcvd_by_value(const double       const_vec[3],
               const cs_lnum_t    n_elts,
               const cs_lnum_t   *elt_ids,
               double             values[])
{
  const cs_adjacency_t  *c2v = cs_cdo_connect->c2v;
  const cs_real_t  *dual_vol = cs_cdo_quant->dcell_vol; /* scan by c2v */

  if (elt_ids == NULL) {

    for (cs_lnum_t c_id = 0; c_id < n_elts; c_id++) {
      for (cs_lnum_t j = c2v->idx[c_id]; j < c2v->idx[c_id+1]; j++) {
        const cs_lnum_t  v_id = c2v->ids[j];
        const cs_real_t  vol_vc = dual_vol[j];

        values[3*v_id   ] += vol_vc*const_vec[0];
        values[3*v_id +1] += vol_vc*const_vec[1];
        values[3*v_id +2] += vol_vc*const_vec[2];

      }
    }

  }
  else { /* Loop on selected cells */

    for (cs_lnum_t i = 0; i < n_elts; i++) {
      const cs_lnum_t  c_id = elt_ids[i];
      for (cs_lnum_t  j = c2v->idx[c_id]; j < c2v->idx[c_id+1]; j++) {
        const cs_lnum_t  v_id = c2v->ids[j];
        const cs_real_t  vol_vc = dual_vol[j];

        values[3*v_id   ] += vol_vc*const_vec[0];
        values[3*v_id +1] += vol_vc*const_vec[1];
        values[3*v_id +2] += vol_vc*const_vec[2];
      }
    }

  }

}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Compute the integral over a (primal) cell of a value related to
 *         scalar density field
 *
 * \param[in]      const_val   constant value
 * \param[in]      n_loc_elts  number of elements to consider
 * \param[in]      elt_ids     pointer to the list od selected ids
 * \param[in, out] values      pointer to the computed values
 */
/*----------------------------------------------------------------------------*/

static void
_pcsd_by_value(const double       const_val,
               const cs_lnum_t    n_elts,
               const cs_lnum_t   *elt_ids,
               double             values[])
{
  const cs_cdo_quantities_t  *quant = cs_cdo_quant;

  if (elt_ids == NULL) { /* All the support entities are selected */
#   pragma omp parallel for if (quant->n_cells > CS_THR_MIN)
    for (cs_lnum_t c_id = 0; c_id < quant->n_cells; c_id++)
      values[c_id] = quant->cell_vol[c_id]*const_val;
  }

  else { /* Loop on selected cells */
#   pragma omp parallel for if (n_elts > CS_THR_MIN)
    for (cs_lnum_t i = 0; i < n_elts; i++) {
      cs_lnum_t  c_id = elt_ids[i];
      values[c_id] = quant->cell_vol[c_id]*const_val;
    }
  }

}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Compute the integral over a (primal) cell of a vector-valued
 *         density field
 *
 * \param[in]      const_vec   constant values
 * \param[in]      n_loc_elts  number of elements to consider
 * \param[in]      elt_ids     pointer to the list od selected ids
 * \param[in, out] values      pointer to the computed values
 */
/*----------------------------------------------------------------------------*/

static void
_pcvd_by_value(const double        const_vec[3],
               const cs_lnum_t     n_elts,
               const cs_lnum_t    *elt_ids,
               double              values[])
{
  const cs_real_t  *vol = cs_cdo_quant->cell_vol;

  if (elt_ids == NULL) { /* All the support entities are selected */
#   pragma omp parallel for if (cs_cdo_quant->n_cells > CS_THR_MIN)
    for (cs_lnum_t c_id = 0; c_id < cs_cdo_quant->n_cells; c_id++) {
      const cs_real_t  vol_c = vol[c_id];
      values[3*c_id]   = vol_c*const_vec[0];
      values[3*c_id+1] = vol_c*const_vec[1];
      values[3*c_id+2] = vol_c*const_vec[2];
    }
  }

  else { /* Loop on selected cells */
#   pragma omp parallel for if (n_elts > CS_THR_MIN)
    for (cs_lnum_t i = 0; i < n_elts; i++) {
      const cs_lnum_t  c_id = elt_ids[i];
      const cs_real_t  vol_c = vol[c_id];
      values[3*c_id  ] = vol_c*const_vec[0];
      values[3*c_id+1] = vol_c*const_vec[1];
      values[3*c_id+2] = vol_c*const_vec[2];
    }
  }

}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Get the values at each primal faces for a scalar potential
 *         defined by an analytical function on a selection of (primal) cells
 *
 * \param[in]      ana         pointer to the analytic function
 * \param[in]      input       NULL or pointer to a structure cast on-the-fly
 * \param[in]      n_loc_elts  number of elements to consider
 * \param[in]      elt_ids     pointer to the list od selected ids
 * \param[in, out] values      pointer to the computed values
 */
/*----------------------------------------------------------------------------*/

static void
_pfsp_by_analytic(cs_analytic_func_t    *ana,
                  void                  *input,
                  const cs_lnum_t        n_elts,
                  const cs_lnum_t       *elt_ids,
                  double                 values[])
{
  const double  tcur = cs_time_step->t_cur;
  const cs_cdo_quantities_t  *quant = cs_cdo_quant;
  const cs_adjacency_t  *c2f = cs_cdo_connect->c2f;

  /* Initialize todo array */
  bool  *todo = NULL;

  BFT_MALLOC(todo, quant->n_faces, bool);
# pragma omp parallel for if (quant->n_faces > CS_THR_MIN)
  for (cs_lnum_t f_id = 0; f_id < quant->n_faces; f_id++)
    todo[f_id] = true;

  for (cs_lnum_t i = 0; i < n_elts; i++) { // Loop on selected cells

    cs_lnum_t  c_id = elt_ids[i];

    for (cs_lnum_t j = c2f->idx[c_id]; j < c2f->idx[c_id+1]; j++) {

      cs_lnum_t  f_id = c2f->ids[j];
      if (todo[f_id]) {
        const cs_real_t  *xf = cs_quant_set_face_center(f_id, quant);
        ana(tcur, 1, NULL, xf, false,  input, values + f_id);
        todo[f_id] = false;
      }

    } // Loop on cell faces

  } // Loop on selected cells

  BFT_FREE(todo);
}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Get the values at each primal vertices for a scalar potential
 *         defined by an analytical function on a selection of (primal) cells
 *
 * \param[in]      ana         pointer to the analytic function
 * \param[in]      input       NULL or pointer to a structure cast on-the-fly
 * \param[in]      n_elts      number of elements to consider
 * \param[in]      elt_ids     pointer to the list od selected ids
 * \param[in, out] values      pointer to the computed values
 */
/*----------------------------------------------------------------------------*/

static void
_pvsp_by_analytic(cs_analytic_func_t    *ana,
                  void                  *input,
                  const cs_lnum_t        n_elts,
                  const cs_lnum_t       *elt_ids,
                  double                 values[])
{
  const double  tcur = cs_time_step->t_cur;
  const cs_cdo_quantities_t  *quant = cs_cdo_quant;
  const cs_adjacency_t  *c2v = cs_cdo_connect->c2v;

  /* Initialize todo array */
  cs_lnum_t  *vtx_lst = NULL;

  BFT_MALLOC(vtx_lst, quant->n_vertices, cs_lnum_t);
# pragma omp parallel for if (quant->n_vertices > CS_THR_MIN)
  for (cs_lnum_t v_id = 0; v_id < quant->n_vertices; v_id++)
    vtx_lst[v_id] = -1; // No flag

  for (cs_lnum_t i = 0; i < n_elts; i++) { // Loop on selected cells

    const cs_lnum_t  c_id = elt_ids[i];
    for (cs_lnum_t j = c2v->idx[c_id]; j < c2v->idx[c_id+1]; j++) {

      cs_lnum_t  v_id = c2v->ids[j];
      if (vtx_lst[v_id] == -1) // Not encountered yet
        vtx_lst[v_id] = v_id;

    } // Loop on cell vertices
  } // Loop on selected cells

  /* Count number of selected vertices */
  cs_lnum_t  n_selected_vertices = 0;
  for (cs_lnum_t v_id = 0; v_id < quant->n_vertices; v_id++) {
    if (vtx_lst[v_id] == v_id)
      vtx_lst[n_selected_vertices++] = v_id;
  }

  /* One call for all selected vertices */
  ana(tcur, n_selected_vertices, vtx_lst, quant->vtx_coord,
      false,  // compacted output ?
      input,
      values);

  BFT_FREE(vtx_lst);
}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Get the values at each primal faces for a scalar potential
 *
 * \param[in]      const_val   constant value
 * \param[in]      n_elts      number of elements to consider
 * \param[in]      elt_ids     pointer to the list od selected ids
 * \param[in, out] values      pointer to the array storing the values
 */
/*----------------------------------------------------------------------------*/

static void
_pfsp_by_value(const double       const_val,
               cs_lnum_t          n_elts,
               const cs_lnum_t   *elt_ids,
               double             values[])
{
  const cs_cdo_quantities_t  *quant = cs_cdo_quant;
  const cs_adjacency_t  *c2f = cs_cdo_connect->c2f;

  /* Initialize todo array */
  bool  *todo = NULL;

  BFT_MALLOC(todo, quant->n_faces, bool);
# pragma omp parallel for if (quant->n_faces > CS_THR_MIN)
  for (cs_lnum_t f_id = 0; f_id < quant->n_faces; f_id++)
    todo[f_id] = true;

  for (cs_lnum_t i = 0; i < n_elts; i++) { // Loop on selected cells

    cs_lnum_t  c_id = elt_ids[i];

    for (cs_lnum_t j = c2f->idx[c_id]; j < c2f->idx[c_id+1]; j++) {

      cs_lnum_t  f_id = c2f->ids[j];
      if (todo[f_id])
        values[f_id] = const_val, todo[f_id] = false;

    } // Loop on cell vertices

  } // Loop on selected cells

  BFT_FREE(todo);
}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Unmarked vertices belonging to the frontier of the cell selection
 *
 * \param[in]      c_id          id of the cell to treat
 * \param[in]      cell_tag      tag for each cell
 * \param[in, out] vtx_tag       tag for each vertex
 */
/*----------------------------------------------------------------------------*/

static void
_untag_frontier_vertices(cs_lnum_t      c_id,
                         const bool     cell_tag[],
                         cs_lnum_t      vtx_tag[])
{
  const cs_mesh_t  *m = cs_glob_mesh;
  const cs_lnum_t  *f2v_idx = m->i_face_vtx_idx;
  const cs_lnum_t  *f2v_lst = m->i_face_vtx_lst;
  const cs_adjacency_t  *c2f = cs_cdo_connect->c2f;

  for (cs_lnum_t j = c2f->idx[c_id]; j < c2f->idx[c_id+1]; j++) {

    const cs_lnum_t  f_id = c2f->ids[j];
    if (f_id < m->n_i_faces) { /* interior face */

      if (cell_tag[m->i_face_cells[f_id][0]] == false ||
          cell_tag[m->i_face_cells[f_id][1]] == false) {

        for (cs_lnum_t i = f2v_idx[f_id]; i < f2v_idx[f_id+1]; i++)
          vtx_tag[f2v_lst[i]] = 0; // untag

      }
    } // This face belongs to the frontier of the selection (only interior)

  } // Loop on cell faces

}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Define a value to each DoF such that a given quantity is put inside
 *         the volume associated to the list of cells
 *
 * \param[in]      quantity_val  amount of quantity to distribute
 * \param[in]      n_elts        number of elements to consider
 * \param[in]      elt_ids       pointer to the list od selected ids
 * \param[in, out] values        pointer to the array storing the values
 */
/*----------------------------------------------------------------------------*/

static void
_pvsp_by_qov(const double       quantity_val,
             cs_lnum_t          n_elts,
             const cs_lnum_t   *elt_ids,
             double             values[])
{
  const cs_mesh_t  *m = cs_glob_mesh;
  const cs_cdo_quantities_t  *quant = cs_cdo_quant;
  const cs_lnum_t  n_cells = quant->n_cells;
  const cs_lnum_t  n_vertices = quant->n_vertices;
  const cs_real_t  *dc_vol = quant->dcell_vol;
  const cs_adjacency_t  *c2v = cs_cdo_connect->c2v;

  cs_lnum_t  *vtx_tag = NULL;
  bool  *cell_tag = NULL;

  BFT_MALLOC(vtx_tag, n_vertices, cs_lnum_t);
  BFT_MALLOC(cell_tag, m->n_cells_with_ghosts, bool);

  if (n_elts < n_cells) { /* Only some cells are selected */

#   pragma omp parallel for if (n_vertices > CS_THR_MIN)
    for (cs_lnum_t v_id = 0; v_id < n_vertices; v_id++)
      vtx_tag[v_id] = 0;
#   pragma omp parallel for if (n_cells > CS_THR_MIN)
    for (cs_lnum_t c_id = 0; c_id < m->n_cells_with_ghosts; c_id++)
      cell_tag[c_id] = false;

  /* First pass: flag cells and vertices */
#   pragma omp parallel for if (n_elts > CS_THR_MIN)
    for (cs_lnum_t i = 0; i < n_elts; i++) { // Loop on selected cells

      const cs_lnum_t  c_id = elt_ids[i];
      cell_tag[c_id] = true;
      for (cs_lnum_t j = c2v->idx[c_id]; j < c2v->idx[c_id+1]; j++)
        vtx_tag[c2v->ids[j]] = -1; // activated

    } // Loop on selected cells

  }
  else { /* All cells are selected */

    assert(n_cells == n_elts);

#   pragma omp parallel for if (n_vertices > CS_THR_MIN)
    for (cs_lnum_t v_id = 0; v_id < n_vertices; v_id++)
      vtx_tag[v_id] = -1;

#   pragma omp parallel for if (n_cells > CS_THR_MIN)
    for (cs_lnum_t c_id = 0; c_id < n_cells; c_id++)
      cell_tag[c_id] = true;
    for (cs_lnum_t c_id = n_cells; c_id < m->n_cells_with_ghosts; c_id++)
      cell_tag[c_id] = false;

  }

  if (m->halo != NULL)
    cs_halo_sync_untyped(m->halo, CS_HALO_STANDARD, sizeof(bool), cell_tag);

  /* Second pass: detect cells at the frontier of the selection */
  if (n_elts < n_cells) { /* Only some cells are selected */

    for (cs_lnum_t i = 0; i < n_elts; i++)
      _untag_frontier_vertices(elt_ids[i], cell_tag, vtx_tag);

  }
  else {

    for (cs_lnum_t i = 0; i < n_cells; i++)
      _untag_frontier_vertices(i, cell_tag, vtx_tag);

  }

  /* Handle parallelism */
  if (cs_glob_n_ranks > 1)
    cs_interface_set_max(cs_cdo_connect->interfaces[CS_CDO_CONNECT_VTX_SCA],
                         n_vertices,
                         1,           // stride
                         true,        // interlace, not useful here
                         CS_LNUM_TYPE,
                         (void *)vtx_tag);

  /* Third pass: compute the (really) available volume */
  double  volume_marked = 0.;

  if (elt_ids != NULL) { /* Only some cells are selected */

#   pragma omp parallel for reduction(+:volume_marked) if (n_elts > CS_THR_MIN)
    for (cs_lnum_t i = 0; i < n_elts; i++) { // Loop on selected cells

      const cs_lnum_t  c_id = elt_ids[i];
      for (cs_lnum_t j = c2v->idx[c_id]; j < c2v->idx[c_id+1]; j++)
        if (vtx_tag[c2v->ids[j]] == -1) // activated
          volume_marked += dc_vol[j]; // | dual_cell cap cell |

    } // Loop on selected cells

  }
  else { /* elt_ids == NULL => all cells are selected */

# pragma omp parallel for reduction(+:volume_marked) if (n_cells > CS_THR_MIN)
    for (cs_lnum_t c_id = 0; c_id < n_cells; c_id++) {
      for (cs_lnum_t j = c2v->idx[c_id]; j < c2v->idx[c_id+1]; j++)
        if (vtx_tag[c2v->ids[j]] == -1) // activated
          volume_marked += dc_vol[j]; // | dual_cell cap cell |
    }

  }

  /* Handle parallelism */
  if (cs_glob_n_ranks > 1)
    cs_parall_sum(1, CS_DOUBLE, &volume_marked);

  double val_to_set = quantity_val;
  if (volume_marked > 0)
    val_to_set /= volume_marked;

  if (n_elts < n_cells) { /* Only some cells are selected */

#   pragma omp parallel for if (n_vertices > CS_THR_MIN)
    for (cs_lnum_t v_id = 0; v_id < n_vertices; v_id++)
      if (vtx_tag[v_id] == -1)
        values[v_id] = val_to_set;

  }
  else { /* All cells are selected */

#   pragma omp parallel for if (n_vertices > CS_THR_MIN)
    for (cs_lnum_t v_id = 0; v_id < n_vertices; v_id++)
      values[v_id] = val_to_set;

  }

  BFT_FREE(cell_tag);
  BFT_FREE(vtx_tag);
}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Get the values at each primal vertices for a scalar potential
 *
 * \param[in]      const_val   constant value
 * \param[in]      n_elts      number of elements to consider
 * \param[in]      elt_ids     pointer to the list od selected ids
 * \param[in, out] values      pointer to the array storing the values
 */
/*----------------------------------------------------------------------------*/

static void
_pvsp_by_value(cs_real_t          const_val,
               cs_lnum_t          n_elts,
               const cs_lnum_t   *elt_ids,
               double             values[])
{
  const cs_cdo_quantities_t  *quant = cs_cdo_quant;
  const cs_adjacency_t  *c2v = cs_cdo_connect->c2v;

  /* Initialize todo array */
  bool  *todo = NULL;

  BFT_MALLOC(todo, quant->n_vertices, bool);

# pragma omp parallel for if (quant->n_vertices > CS_THR_MIN)
  for (cs_lnum_t v_id = 0; v_id < quant->n_vertices; v_id++)
    todo[v_id] = true;

  for (cs_lnum_t i = 0; i < n_elts; i++) { // Loop on selected cells

    cs_lnum_t  c_id = elt_ids[i];

    for (cs_lnum_t j = c2v->idx[c_id]; j < c2v->idx[c_id+1]; j++) {

      cs_lnum_t  v_id = c2v->ids[j];
      if (todo[v_id])
        values[v_id] = const_val, todo[v_id] = false;

    } // Loop on cell vertices

  } // Loop on selected cells

  BFT_FREE(todo);
}

/*============================================================================
 * Public function prototypes
 *============================================================================*/

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Set shared pointers to main domain members
 *
 * \param[in]  quant       additional mesh quantities struct.
 * \param[in]  connect     pointer to a cs_cdo_connect_t struct.
 * \param[in]  time_step   pointer to a time step structure
 */
/*----------------------------------------------------------------------------*/

void
cs_evaluate_set_shared_pointers(const cs_cdo_quantities_t    *quant,
                                const cs_cdo_connect_t       *connect,
                                const cs_time_step_t         *time_step)
{
  /* Assign static const pointers */
  cs_cdo_quant = quant;
  cs_cdo_connect = connect;
  cs_time_step = time_step;
}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Compute the value related to each DoF in the case of a density field
 *         The value defined by the analytic function is by unity of volume
 *
 * \param[in]      dof_flag    indicate where the evaluation has to be done
 * \param[in]      def         pointer to a cs_xdef_t structure
 * \param[in, out] retval      pointer to the computed values
 */
/*----------------------------------------------------------------------------*/

void
cs_evaluate_density_by_analytic(cs_flag_t           dof_flag,
                                const cs_xdef_t    *def,
                                double              retval[])
{
  /* Sanity check */
  if (retval == NULL)
    bft_error(__FILE__, __LINE__, 0, _err_empty_array, __func__);
  assert(def != NULL);
  assert(def->support == CS_XDEF_SUPPORT_VOLUME);

    /* Retrieve information from mesh location structures */
  const cs_volume_zone_t  *z = cs_volume_zone_by_id(def->z_id);

  cs_evaluate_tetra_integral_t  *qfunc = NULL;
  switch (def->qtype) {

  case CS_QUADRATURE_BARY: /* Barycenter of the tetrahedral subdiv. */
  case CS_QUADRATURE_BARY_SUBDIV:
    qfunc = _analytic_scalar_tet1;
    break;

  case CS_QUADRATURE_HIGHER: /* Quadrature with a unique weight */
    qfunc = _analytic_scalar_tet4;
    break;

  case CS_QUADRATURE_HIGHEST: /* Most accurate quadrature available */
    qfunc = _analytic_scalar_tet5;
    break;

  default:
    bft_error(__FILE__, __LINE__, 0, _("Invalid quadrature type.\n"));

  } /* Which type of quadrature to use */

  /* Perform the evaluation */
  if (dof_flag & CS_FLAG_SCALAR) { /* DoF is scalar-valued */

    cs_xdef_analytic_input_t  *anai = (cs_xdef_analytic_input_t *)def->input;

    if (cs_flag_test(dof_flag, cs_flag_primal_cell)) {

      _pcsd_by_analytic(anai->func, anai->input,
                        z->n_cells, z->cell_ids, qfunc, retval);

    }
    else if (cs_flag_test(dof_flag, cs_flag_dual_cell)) {

      _dcsd_by_analytic(anai->func, anai->input,
                        z->n_cells, z->cell_ids, qfunc,
                        retval);

    }
    else
      bft_error(__FILE__, __LINE__, 0, _err_not_handled, __func__);

  }
  else
    bft_error(__FILE__, __LINE__, 0, _err_not_handled, __func__);
}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Evaluate the quantity defined by a value in the case of a density
 *         field for all the degrees of freedom
 *         Accessor to the value is by unit of volume
 *
 * \param[in]      dof_flag  indicate where the evaluation has to be done
 * \param[in]      def       pointer to a cs_xdef_t structure
 * \param[in, out] retval    pointer to the computed values
 */
/*----------------------------------------------------------------------------*/

void
cs_evaluate_density_by_value(cs_flag_t          dof_flag,
                             const cs_xdef_t   *def,
                             double             retval[])
{
  /* Sanity check */
  if (retval == NULL)
    bft_error(__FILE__, __LINE__, 0, _err_empty_array, __func__);
  assert(def != NULL);
  assert(def->support == CS_XDEF_SUPPORT_VOLUME);

  /* Retrieve information from mesh location structures */
  const cs_volume_zone_t  *z = cs_volume_zone_by_id(def->z_id);

  /* Perform the evaluation */
  if (dof_flag & CS_FLAG_SCALAR) { /* DoF is scalar-valued */

    const cs_real_t  *constant_val = (const cs_real_t *)def->input;

    if (cs_flag_test(dof_flag, cs_flag_primal_cell))
      _pcsd_by_value(constant_val[0], z->n_cells, z->cell_ids, retval);
    else if (cs_flag_test(dof_flag, cs_flag_dual_cell))
      _dcsd_by_value(constant_val[0], z->n_cells, z->cell_ids, retval);
    else
      bft_error(__FILE__, __LINE__, 0, _err_not_handled, __func__);

  }
  else if (dof_flag & CS_FLAG_VECTOR) { /* DoF is vector-valued */

    const cs_real_t  *constant_vec = (const cs_real_t *)def->input;

    if (cs_flag_test(dof_flag, cs_flag_primal_cell))
      _pcvd_by_value(constant_vec, z->n_cells, z->cell_ids, retval);
    else if (cs_flag_test(dof_flag, cs_flag_dual_cell))
      _dcvd_by_value(constant_vec, z->n_cells, z->cell_ids, retval);
    else
      bft_error(__FILE__, __LINE__, 0, _err_not_handled, __func__);

  }
  else
    bft_error(__FILE__, __LINE__, 0, _err_not_handled, __func__);

}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Evaluate the quantity attached to a potential field for all the DoFs
 *         when the definition relies on an analytic expression
 *
 * \param[in]      dof_flag    indicate where the evaluation has to be done
 * \param[in]      def       pointer to a cs_xdef_t pointer
 * \param[in, out] retval      pointer to the computed values
 */
/*----------------------------------------------------------------------------*/

void
cs_evaluate_potential_by_analytic(cs_flag_t           dof_flag,
                                  const cs_xdef_t    *def,
                                  double              retval[])
{
  /* Sanity check */
  if (retval == NULL)
    bft_error(__FILE__, __LINE__, 0, _err_empty_array, __func__);
  assert(def != NULL);
  assert(def->support == CS_XDEF_SUPPORT_VOLUME);

  int  stride = 0;
  if (dof_flag & CS_FLAG_SCALAR)
    stride = 1;
  else if (dof_flag & CS_FLAG_VECTOR)
    stride = 3;
  else
    bft_error(__FILE__, __LINE__, 0, _err_not_handled, __func__);

  cs_xdef_analytic_input_t  *anai = (cs_xdef_analytic_input_t *)def->input;

  const cs_volume_zone_t  *z = cs_volume_zone_by_id(def->z_id);
  const cs_cdo_quantities_t  *quant = cs_cdo_quant;
  const cs_cdo_connect_t  *connect = cs_cdo_connect;
  const double  tcur = cs_time_step->t_cur;

  /* Perform the evaluation */
  if (cs_flag_test(dof_flag, cs_flag_primal_vtx)) {

    if (def->meta & CS_FLAG_FULL_LOC)
      anai->func(tcur,
                 quant->n_vertices, NULL, quant->vtx_coord,
                 false,  // compacted output ?
                 anai->input,
                 retval);
    else
      _pvsp_by_analytic(anai->func, anai->input,
                        z->n_cells, z->cell_ids,
                        retval);

    if (cs_glob_n_ranks > 1)
      cs_range_set_sync(connect->range_sets[CS_CDO_CONNECT_VTX_SCA],
                        CS_DOUBLE,
                        stride,
                        (void *)retval);

  } /* Located at primal vertices */

  else if (cs_flag_test(dof_flag, cs_flag_primal_face)) {

    if (def->meta & CS_FLAG_FULL_LOC) {

      /* All the support entities are selected:
         - First pass: interior faces
         - Second pass: border faces */
      anai->func(tcur,
                 quant->n_i_faces, NULL, quant->i_face_center,
                 true, // compacted output
                 anai->input,
                 retval);
      anai->func(tcur,
                 quant->n_b_faces, NULL, quant->b_face_center,
                 true, // compacted output
                 anai->input,
                 retval + quant->n_i_faces);

    }
    else
      _pfsp_by_analytic(anai->func, anai->input,
                        z->n_cells, z->cell_ids,
                        retval);

    if (cs_glob_n_ranks > 1)
      cs_range_set_sync(connect->range_sets[CS_CDO_CONNECT_FACE_SP0],
                        CS_DOUBLE,
                        stride,
                        (void *)retval);

  } /* Located at primal faces */

  else if (cs_flag_test(dof_flag, cs_flag_primal_cell) ||
           cs_flag_test(dof_flag, cs_flag_dual_vtx)) {

    if (def->meta & CS_FLAG_FULL_LOC) /* All cells are selected */
      anai->func(tcur,
                 quant->n_cells, NULL, quant->cell_centers,
                 false, // compacted output
                 anai->input,
                 retval);
    else
      anai->func(tcur,
                 z->n_cells, z->cell_ids, quant->cell_centers,
                 false, // compacted output
                 anai->input,
                 retval);

    /* No sync since theses values are computed by only one rank */

  } /* Located at primal cells or dual vertices */
  else
    bft_error(__FILE__, __LINE__, 0, _err_not_handled, __func__);

}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Define a value to each DoF in the case of a potential field in order
 *         to put a given quantity inside the volume associated to the zone
 *         attached to the given definition
 *
 * \param[in]      dof_flag  indicate where the evaluation has to be done
 * \param[in]      def       pointer to a cs_xdef_t pointer
 * \param[in, out] retval    pointer to the computed values
 */
/*----------------------------------------------------------------------------*/

void
cs_evaluate_potential_by_qov(cs_flag_t          dof_flag,
                             const cs_xdef_t   *def,
                             double             retval[])
{
  /* Sanity check */
  if (retval == NULL)
    bft_error(__FILE__, __LINE__, 0, _err_empty_array, __func__);
  assert(def != NULL);
  assert(def->support == CS_XDEF_SUPPORT_VOLUME);

  const cs_real_t  *input = (cs_real_t *)def->input;
  const cs_volume_zone_t  *z = cs_volume_zone_by_id(def->z_id);

  /* Perform the evaluation */
  bool check = false;
  if (dof_flag & CS_FLAG_SCALAR) { /* DoF is scalar-valued */

    const cs_real_t  const_val = input[0];

    if (cs_flag_test(dof_flag, cs_flag_primal_vtx))
      _pvsp_by_qov(const_val, z->n_cells, z->cell_ids, retval);
    check = true;

  } /* Located at primal vertices */

  if (!check)
    bft_error(__FILE__, __LINE__, 0,
              _(" Stop evaluating a potential from 'quantity over volume'.\n"
                " This situation is not handled yet."));
}

/*----------------------------------------------------------------------------*/
/*!
 * \brief  Evaluate the quantity attached to a potential field for all the DoFs
 *
 * \param[in]      dof_flag  indicate where the evaluation has to be done
 * \param[in]      def       pointer to a cs_xdef_t pointer
 * \param[in, out] retval    pointer to the computed values
 */
/*----------------------------------------------------------------------------*/

void
cs_evaluate_potential_by_value(cs_flag_t          dof_flag,
                               const cs_xdef_t   *def,
                               double             retval[])
{
  /* Sanity check */
  if (retval == NULL)
    bft_error(__FILE__, __LINE__, 0, _err_empty_array, __func__);
  assert(def != NULL);
  assert(def->support == CS_XDEF_SUPPORT_VOLUME);

  const cs_cdo_quantities_t  *quant = cs_cdo_quant;
  const cs_real_t  *input = (cs_real_t *)def->input;
  const cs_volume_zone_t  *z = cs_volume_zone_by_id(def->z_id);

  /* Perform the evaluation */
  if (dof_flag & CS_FLAG_SCALAR) { /* DoF is scalar-valued */

    const cs_real_t  const_val = input[0];

    if (cs_flag_test(dof_flag, cs_flag_primal_vtx)) {

      if (def->meta & CS_FLAG_FULL_LOC) {
#       pragma omp parallel for if (quant->n_vertices > CS_THR_MIN)
        for (cs_lnum_t v_id = 0; v_id < quant->n_vertices; v_id++)
          retval[v_id] = const_val;
      }
      else
        _pvsp_by_value(const_val, z->n_cells, z->cell_ids, retval);

    } /* Located at primal vertices */

    else if (cs_flag_test(dof_flag, cs_flag_primal_face)) {

      if (def->meta & CS_FLAG_FULL_LOC) {
#       pragma omp parallel for if (quant->n_faces > CS_THR_MIN)
        for (cs_lnum_t f_id = 0; f_id < quant->n_faces; f_id++)
          retval[f_id] = const_val;
      }
      else
        _pfsp_by_value(const_val, z->n_cells, z->cell_ids, retval);

    } /* Located at primal faces */

    else if (cs_flag_test(dof_flag, cs_flag_primal_cell) ||
             cs_flag_test(dof_flag, cs_flag_dual_vtx)) {

      if (def->meta & CS_FLAG_FULL_LOC) {
#       pragma omp parallel for if (quant->n_cells > CS_THR_MIN)
        for (cs_lnum_t c_id = 0; c_id < quant->n_cells; c_id++)
          retval[c_id] = const_val;
      }
      else
        for (cs_lnum_t i = 0; i < z->n_cells; i++) // Loop on selected cells
          retval[z->cell_ids[i]] = const_val;

    } /* Located at primal cells or dual vertices */

    else
      bft_error(__FILE__, __LINE__, 0, _err_not_handled, __func__);

  }
  else
    bft_error(__FILE__, __LINE__, 0, _err_not_handled, __func__);

}

/*----------------------------------------------------------------------------*/

END_C_DECLS
