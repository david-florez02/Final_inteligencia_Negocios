import { HttpClient } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { MatButtonModule } from '@angular/material/button';
import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { FormsModule } from '@angular/forms';

import { SupabaseService } from '../../core/supabase.service';

interface ProfileData { id: string; full_name: string | null; phone: string | null; address: string | null; role: string; }
interface OrderItem { id: number; product_id: number; quantity: number; unit_price: number; total_price: number; products?: { name: string } | null; }
interface Order { id: number; status: string; total_amount: number; created_at: string; items: OrderItem[]; }

@Component({
  selector: 'app-profile-page',
  standalone: true,
  imports: [FormsModule, MatCardModule, MatButtonModule, MatFormFieldModule, MatInputModule, DecimalPipe],
  template: `
    <div class="row">
      <mat-card class="half">
        <mat-card-header><mat-card-title>Mis datos</mat-card-title></mat-card-header>
        <mat-card-content>
          <form (submit)="save()" class="form">
            <mat-form-field appearance="outline">
              <mat-label>Nombre completo</mat-label>
              <input matInput [ngModel]="fullName()" [ngModelOptions]="{standalone: true}" (ngModelChange)="fullName.set($event)" required>
            </mat-form-field>
            <mat-form-field appearance="outline">
              <mat-label>Teléfono</mat-label>
              <input matInput [ngModel]="phone()" [ngModelOptions]="{standalone: true}" (ngModelChange)="phone.set($event)">
            </mat-form-field>
            <mat-form-field appearance="outline">
              <mat-label>Dirección</mat-label>
              <textarea matInput rows="2" [ngModel]="address()" [ngModelOptions]="{standalone: true}" (ngModelChange)="address.set($event)"></textarea>
            </mat-form-field>
            <button mat-flat-button color="primary" type="submit" [disabled]="saving()">Guardar cambios</button>
            @if (savedMsg()) { <p class="ok">{{ savedMsg() }}</p> }
          </form>
        </mat-card-content>
      </mat-card>

      <mat-card class="half">
        <mat-card-header><mat-card-title>Historial de compras</mat-card-title></mat-card-header>
        <mat-card-content>
          @for (o of orders(); track o.id) {
            <div class="order">
              <div class="head">
                <span>Orden #{{ o.id }} — {{ o.status }}</span>
                <strong>{{ '$' }}{{ o.total_amount | number:'1.2-2' }}</strong>
              </div>
              @for (it of o.items; track it.id) {
                <div class="item-row">{{ it.products?.name ?? 'Producto' }} × {{ it.quantity }} — {{ '$' }}{{ it.total_price | number:'1.2-2' }}</div>
              }
            </div>
          } @empty {
            <p>Aún no hay compras registradas.</p>
          }
        </mat-card-content>
      </mat-card>
    </div>
  `,
  styles: [`
    .row { display: flex; gap: 24px; flex-wrap: wrap; }
    .half { flex: 1; min-width: 320px; }
    .form { display: flex; flex-direction: column; gap: 12px; }
    .order { border-bottom: 1px solid #ececec; padding: 12px 0; }
    .head { display: flex; justify-content: space-between; margin-bottom: 4px; }
    .item-row { color: #555; padding-left: 12px; font-size: 14px; }
    .ok { color: #2e7d32; }
  `],
})
export class ProfilePage implements OnInit {
  private http = inject(HttpClient);
  private supabase = inject(SupabaseService);

  readonly fullName = signal('');
  readonly phone = signal('');
  readonly address = signal('');
  readonly orders = signal<Order[]>([]);
  readonly saving = signal(false);
  readonly savedMsg = signal<string | null>(null);

  ngOnInit(): void {
    void this.load();
  }

  private async load(): Promise<void> {
    this.http.get<ProfileData>('/api/profile/me').subscribe({
      next: (p) => {
        this.fullName.set(p.full_name ?? '');
        this.phone.set(p.phone ?? '');
        this.address.set(p.address ?? '');
      },
    });
    this.http.get<Order[]>('/api/profile/me/orders').subscribe({
      next: (o) => this.orders.set(o),
    });
  }

  async save(): Promise<void> {
    this.saving.set(true);
    this.savedMsg.set(null);
    const body = { full_name: this.fullName(), phone: this.phone(), address: this.address() };
    this.http.put<ProfileData>('/api/profile/me', body).subscribe({
      next: () => { this.saving.set(false); this.savedMsg.set('Perfil actualizado correctamente'); },
      error: () => { this.saving.set(false); this.savedMsg.set('No se pudo actualizar el perfil'); },
    });
  }
}
