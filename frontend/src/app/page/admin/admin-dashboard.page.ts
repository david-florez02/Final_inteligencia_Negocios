import { HttpClient } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { MatButtonModule } from '@angular/material/button';
import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatSelectModule } from '@angular/material/select';
import { FormsModule } from '@angular/forms';

import { SupabaseService } from '../../core/supabase.service';

interface Product { id: number; name: string; description: string | null; price: number; stock: number; category_id: number | null; image_url: string | null; }
interface AdminOrder { id: number; status: string; total_amount: number; users_profile?: { full_name: string } | null; }
interface Metrics { total_orders: number; total_revenue: number; orders_by_status: Record<string, number>; top_products: { product_id: number; units: number; revenue: number }[]; }
interface Draft { id: number | null; name: string; price: number; stock: number; description: string; }

@Component({
  selector: 'app-admin-dashboard-page',
  standalone: true,
  imports: [FormsModule, MatCardModule, MatButtonModule, MatFormFieldModule, MatInputModule, MatSelectModule, DecimalPipe],
  template: `
    <h1>Panel de administración</h1>

    <div class="metrics">
      <mat-card><mat-card-content><h2>{{ metrics()?.total_orders ?? 0 }}</h2><p>Órdenes</p></mat-card-content></mat-card>
      <mat-card><mat-card-content><h2>{{ '$' }}{{ (metrics()?.total_revenue ?? 0) | number:'1.2-2' }}</h2><p>Ingresos</p></mat-card-content></mat-card>
      <mat-card><mat-card-content><h2>{{ metrics()?.orders_by_status?.['pending'] ?? 0 }}</h2><p>Pendientes</p></mat-card-content></mat-card>
    </div>

    <div class="row">
      <mat-card class="half">
        <mat-card-header><mat-card-title>Inventario</mat-card-title></mat-card-header>
        <mat-card-content>
          <form (submit)="saveProduct()" class="form">
            <mat-form-field appearance="outline"><mat-label>Nombre</mat-label>
              <input matInput required [(ngModel)]="draft.name">
            </mat-form-field>
            <mat-form-field appearance="outline"><mat-label>Precio</mat-label>
              <input matInput type="number" required min="0" [(ngModel)]="draft.price">
            </mat-form-field>
            <mat-form-field appearance="outline"><mat-label>Stock</mat-label>
              <input matInput type="number" required min="0" [(ngModel)]="draft.stock">
            </mat-form-field>
            <mat-form-field appearance="outline"><mat-label>Descripción</mat-label>
              <input matInput [(ngModel)]="draft.description">
            </mat-form-field>
            <button mat-flat-button color="primary" type="submit">{{ draft.id ? 'Guardar producto' : 'Crear producto' }}</button>
            @if (draft.id) { <button mat-button type="button" (click)="resetDraft()">Cancelar edición</button> }
          </form>
          @if (formMsg()) { <p>{{ formMsg() }}</p> }
        </mat-card-content>
      </mat-card>

      <mat-card class="half">
        <mat-card-header><mat-card-title>Productos existentes</mat-card-title></mat-card-header>
        <mat-card-content>
          <table>
            <tr><th>Nombre</th><th>Precio</th><th>Stock</th><th></th></tr>
            @for (p of products(); track p.id) {
              <tr>
                <td>{{ p.name }}</td>
                <td>{{ '$' }}{{ p.price | number:'1.2-2' }}</td>
                <td>{{ p.stock }}</td>
                <td>
                  <button mat-icon-button (click)="editProduct(p)"><span>✏️</span></button>
                  <button mat-icon-button (click)="deleteProduct(p.id)"><span>🗑️</span></button>
                </td>
              </tr>
            }
          </table>
        </mat-card-content>
      </mat-card>
    </div>

    <mat-card class="wide">
      <mat-card-header><mat-card-title>Órdenes</mat-card-title></mat-card-header>
      <mat-card-content>
        <table>
          <tr><th>#</th><th>Cliente</th><th>Total</th><th>Estado</th></tr>
          @for (o of orders(); track o.id) {
            <tr>
              <td>{{ o.id }}</td>
              <td>{{ o.users_profile?.full_name ?? '—' }}</td>
              <td>{{ '$' }}{{ o.total_amount | number:'1.2-2' }}</td>
              <td>
                <mat-form-field appearance="outline" class="status-field">
                  <mat-select [ngModel]="o.status" (ngModelChange)="changeStatus(o.id, $event)">
                    @for (s of statuses; track s) { <mat-option [value]="s">{{ s }}</mat-option> }
                  </mat-select>
                </mat-form-field>
              </td>
            </tr>
          }
        </table>
      </mat-card-content>
    </mat-card>
  `,
  styles: [`
    .metrics { display: flex; gap: 16px; margin-bottom: 24px; }
    .metrics mat-card { flex: 1; text-align: center; }
    .row { display: flex; gap: 24px; flex-wrap: wrap; }
    .half { flex: 1; min-width: 320px; }
    .wide { margin-top: 24px; }
    .form { display: flex; flex-direction: column; gap: 8px; }
    table { width: 100%; border-collapse: collapse; }
    th, td { text-align: left; padding: 8px; border-bottom: 1px solid #eee; }
    .status-field { width: 160px; }
  `],
})
export class AdminDashboardPage implements OnInit {
  private http = inject(HttpClient);
  private supabase = inject(SupabaseService);

  readonly statuses = ['pending', 'processing', 'shipped', 'delivered', 'cancelled'];
  readonly products = signal<Product[]>([]);
  readonly orders = signal<AdminOrder[]>([]);
  readonly metrics = signal<Metrics | null>(null);
  readonly formMsg = signal<string | null>(null);
  draft: Draft = { id: null, name: '', price: 0, stock: 0, description: '' };

  ngOnInit(): void { void this.refresh(); }

  private async headers(): Promise<Record<string, string>> { return await this.supabase.authHeaders(); }

  private async refresh(): Promise<void> {
    const headers = await this.headers();
    this.http.get<Product[]>('/api/products').subscribe({ next: (p) => this.products.set(p) });
    this.http.get<AdminOrder[]>('/api/admin/orders').subscribe({ next: (o) => this.orders.set(o) });
    this.http.get<Metrics>('/api/admin/metrics').subscribe({ next: (m) => this.metrics.set(m) });
  }

  editProduct(p: Product): void {
    this.draft = { id: p.id, name: p.name, price: p.price, stock: p.stock, description: p.description ?? '' };
  }

  resetDraft(): void { this.draft = { id: null, name: '', price: 0, stock: 0, description: '' }; }

  async saveProduct(): Promise<void> {
    const headers = await this.headers();
    const body = { name: this.draft.name, price: this.draft.price, stock: this.draft.stock, description: this.draft.description || null };
    if (this.draft.id) {
      this.http.put<Product>(`/api/admin/products/${this.draft.id}`, body).subscribe({
        next: () => { void this.refresh(); this.resetDraft(); this.formMsg.set('Producto actualizado'); },
        error: () => this.formMsg.set('No se pudo actualizar'),
      });
    } else {
      this.http.post<Product>('/api/admin/products', body).subscribe({
        next: () => { void this.refresh(); this.resetDraft(); this.formMsg.set('Producto creado'); },
        error: () => this.formMsg.set('No se pudo crear'),
      });
    }
  }

  async deleteProduct(productId: number): Promise<void> {
    const headers = await this.headers();
    this.http.delete(`/api/admin/products/${productId}`).subscribe(() => void this.refresh());
  }

  async changeStatus(orderId: number, status: string): Promise<void> {
    const headers = await this.headers();
    this.http.patch(`/api/admin/orders/${orderId}/status`, { status })
      .subscribe(() => void this.refresh());
  }
}
